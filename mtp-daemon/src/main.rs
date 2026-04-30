mod protocol;

use bytes::Bytes;
use futures::stream;
use mtp_rs::mtp::{MtpDevice, NewObjectInfo, Storage};
use mtp_rs::ptp::{AssociationType, ObjectInfo};
use protocol::*;
use std::io::{self, BufRead, Write};
use std::path::Path;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::RwLock;

// FFI to IOKit helper that seizes USB devices from the macOS kernel driver.
#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn seize_usb_device(vendor_id: u16, product_id: u16, serial: *const std::ffi::c_char) -> i32;
}

struct DaemonState {
    device: Option<MtpDevice>,
    storages: Vec<Storage>,
}

impl DaemonState {
    fn new() -> Self {
        Self {
            device: None,
            storages: Vec::new(),
        }
    }
}

fn send_response(id: u64, status: ResponseStatus) {
    let resp = Response { id, status };
    let json = serde_json::to_string(&resp).unwrap();
    let stdout = io::stdout();
    let mut out = stdout.lock();
    writeln!(out, "{}", json).unwrap();
    out.flush().unwrap();
}

fn ok(id: u64, data: serde_json::Value) {
    send_response(id, ResponseStatus::Ok { data });
}

fn err(id: u64, msg: impl Into<String>) {
    send_response(
        id,
        ResponseStatus::Error {
            message: msg.into(),
        },
    );
}

fn progress(id: u64, bytes: u64, total: Option<u64>) {
    send_response(
        id,
        ResponseStatus::Progress {
            data: serde_json::json!({
                "bytes": bytes,
                "total": total,
            }),
        },
    );
}

async fn ensure_connected(state: &Arc<RwLock<DaemonState>>) -> Result<(), String> {
    {
        let st = state.read().await;
        if st.device.is_some() {
            return Ok(());
        }
    }

    // On macOS, the AppleUSBPTP kernel driver holds MTP interfaces exclusively.
    // We must seize the device via IOKit to release the kernel driver's hold.
    #[cfg(target_os = "macos")]
    {
        let devices =
            MtpDevice::list_devices().map_err(|e| format!("Failed to list devices: {e}"))?;

        if let Some(info) = devices.first() {
            let serial_c = info
                .serial_number
                .as_ref()
                .map(|s| std::ffi::CString::new(s.as_str()).unwrap_or_default());

            let serial_ptr = serial_c
                .as_ref()
                .map(|c| c.as_ptr())
                .unwrap_or(std::ptr::null());

            eprintln!(
                "Seizing USB device {:04x}:{:04x}...",
                info.vendor_id, info.product_id
            );
            let result = unsafe { seize_usb_device(info.vendor_id, info.product_id, serial_ptr) };
            if result == 0 {
                eprintln!("Device seized successfully, waiting for release...");
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
            } else {
                eprintln!("Seize returned {} (may be OK if device not held)", result);
            }
        }
    }

    // Stop competing daemons that may hold the USB device.
    #[cfg(target_os = "macos")]
    {
        kill_process_if_running("ptpcamerad");
        kill_process_if_running("adb");
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    }

    let device = match MtpDevice::open_first().await {
        Ok(d) => d,
        Err(_e) => {
            // Retry: seize again and wait longer
            #[cfg(target_os = "macos")]
            {
                let devices = MtpDevice::list_devices().unwrap_or_default();
                if let Some(info) = devices.first() {
                    let serial_c = info
                        .serial_number
                        .as_ref()
                        .map(|s| std::ffi::CString::new(s.as_str()).unwrap_or_default());
                    let serial_ptr = serial_c
                        .as_ref()
                        .map(|c| c.as_ptr())
                        .unwrap_or(std::ptr::null());
                    unsafe {
                        seize_usb_device(info.vendor_id, info.product_id, serial_ptr);
                    }
                }
                tokio::time::sleep(std::time::Duration::from_millis(1000)).await;
                MtpDevice::open_first()
                    .await
                    .map_err(|e2| format!("No MTP device found: {e2}\n\nThe macOS kernel driver may be holding the device.\nTry unplugging and re-plugging the USB cable."))?
            }
            #[cfg(not(target_os = "macos"))]
            {
                return Err(format!("No MTP device found: {_e}"));
            }
        }
    };

    let storages = device
        .storages()
        .await
        .map_err(|e| format!("Failed to list storages: {e}"))?;

    let mut st = state.write().await;
    st.device = Some(device);
    st.storages = storages;
    Ok(())
}

#[cfg(target_os = "macos")]
fn kill_process_if_running(name: &str) {
    let check = std::process::Command::new("pgrep")
        .arg("-x")
        .arg(name)
        .output();
    match check {
        Ok(output) if output.status.success() => {
            eprintln!("Stopping competing process: {name}");
            let _ = std::process::Command::new("killall").arg(name).output();
        }
        _ => {}
    }
}

fn find_storage_for_path<'a>(storages: &'a [Storage], path: &str) -> Option<&'a Storage> {
    let parts: Vec<&str> = path.trim_start_matches('/').split('/').collect();
    if parts.is_empty() {
        return storages.first();
    }
    let label = parts[0];
    storages
        .iter()
        .find(|s| {
            s.info()
                .description
                .to_lowercase()
                .contains(&label.to_lowercase())
        })
        .or_else(|| storages.first())
}

fn parent_path(path: &str) -> &str {
    match path.rfind('/') {
        Some(pos) if pos > 0 => &path[..pos],
        Some(_) => "/",
        None => "/",
    }
}

fn file_name(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

fn is_directory(info: &ObjectInfo) -> bool {
    // Check MTP association type first
    if matches!(info.association_type, AssociationType::GenericFolder) {
        return true;
    }
    // Fallback: directories often have no extension and size 0
    if info.size == 0 && !info.filename.contains('.') {
        return true;
    }
    false
}

async fn handle_request(req: Request, id: u64, state: &Arc<RwLock<DaemonState>>) {
    match req {
        Request::Ping => ok(id, serde_json::json!({"pong": true})),

        Request::ListDevices => match MtpDevice::list_devices() {
            Ok(devices) => {
                let entries: Vec<DeviceEntry> = devices
                    .into_iter()
                    .map(|d| DeviceEntry {
                        name: format!(
                            "{} {}",
                            d.manufacturer.clone().unwrap_or_default(),
                            d.product.clone().unwrap_or_default()
                        ),
                        serial: d.serial_number.unwrap_or_default(),
                        vendor: d.manufacturer.unwrap_or_default(),
                        product: d.product.unwrap_or_default(),
                        location_id: d.location_id as u32,
                    })
                    .collect();
                ok(id, serde_json::to_value(entries).unwrap());
            }
            Err(e) => err(id, format!("Failed to list devices: {e}")),
        },

        Request::ListStorages => {
            if let Err(e) = ensure_connected(&state).await {
                err(id, e);
                return;
            }
            let st = state.read().await;
            let entries: Vec<StorageEntry> = st
                .storages
                .iter()
                .enumerate()
                .map(|(i, s)| {
                    let info = s.info();
                    StorageEntry {
                        id: i as u32,
                        description: info.description.clone(),
                        free_space: info.free_space_bytes,
                        total_space: info.max_capacity,
                    }
                })
                .collect();
            ok(id, serde_json::to_value(entries).unwrap());
        }

        Request::ListFiles { path } => {
            if let Err(e) = ensure_connected(&state).await {
                err(id, e);
                return;
            }
            let st = state.read().await;
            let storage = match find_storage_for_path(&st.storages, &path) {
                Some(s) => s,
                None => {
                    err(id, "No storage found for path");
                    return;
                }
            };

            let parent_handle = find_dir_handle(storage, &path).await;

            let objects = match storage.list_objects(parent_handle).await {
                Ok(objs) => objs,
                Err(e) => {
                    err(id, format!("Failed to list files: {e}"));
                    return;
                }
            };

            let mut entries = Vec::new();
            for obj in objects {
                let ext = Path::new(&obj.filename)
                    .extension()
                    .and_then(|e| e.to_str())
                    .unwrap_or("")
                    .to_string();

                let dir = is_directory(&obj);
                let obj_path = if path.ends_with('/') {
                    format!("{}{}", path, obj.filename)
                } else {
                    format!("{}/{}", path, obj.filename)
                };

                entries.push(FileEntry {
                    name: obj.filename,
                    path: obj_path,
                    is_directory: dir,
                    size: obj.size,
                    date_modified: obj.modified.and_then(|d| d.format()).unwrap_or_default(),
                    file_extension: ext,
                });
            }
            ok(id, serde_json::to_value(entries).unwrap());
        }

        Request::Download { path, dest } => {
            if let Err(e) = ensure_connected(&state).await {
                err(id, e);
                return;
            }
            let st = state.read().await;
            let storage = match find_storage_for_path(&st.storages, &path) {
                Some(s) => s,
                None => {
                    err(id, "No storage found for path");
                    return;
                }
            };

            let parent = parent_path(&path);
            let target_name = file_name(&path);

            let parent_handle = find_dir_handle(storage, parent).await;
            let objects = match storage.list_objects(parent_handle).await {
                Ok(objs) => objs,
                Err(e) => {
                    err(id, format!("Failed to list directory: {e}"));
                    return;
                }
            };

            let obj = match objects.into_iter().find(|o| o.filename == target_name) {
                Some(o) => o,
                None => {
                    err(id, format!("File not found: {path}"));
                    return;
                }
            };

            let mut file = match tokio::fs::File::create(&dest).await {
                Ok(f) => f,
                Err(e) => {
                    err(id, format!("Failed to create local file: {e}"));
                    return;
                }
            };

            let mut stream = match storage.download_stream(obj.handle).await {
                Ok(s) => s,
                Err(e) => {
                    err(id, format!("Download failed: {e}"));
                    return;
                }
            };

            progress(id, 0, Some(obj.size));
            let mut downloaded = 0;

            while let Some(chunk_result) = stream.next_chunk().await {
                match chunk_result {
                    Ok(chunk) => {
                        if let Err(e) = file.write_all(&chunk).await {
                            err(id, format!("Failed to write to local file: {e}"));
                            return;
                        }
                        downloaded += chunk.len() as u64;
                        progress(id, downloaded, Some(obj.size));
                    }
                    Err(e) => {
                        err(id, format!("Download stream error: {e}"));
                        return;
                    }
                }
            }

            ok(id, serde_json::json!({"bytes": downloaded, "dest": dest}));
        }

        Request::Upload { src, dest_path } => {
            if let Err(e) = ensure_connected(&state).await {
                err(id, e);
                return;
            }

            let file = match tokio::fs::File::open(&src).await {
                Ok(file) => file,
                Err(e) => {
                    err(id, format!("Failed to open source file: {e}"));
                    return;
                }
            };

            let size = match file.metadata().await {
                Ok(metadata) => metadata.len(),
                Err(e) => {
                    err(id, format!("Failed to inspect source file: {e}"));
                    return;
                }
            };

            let st = state.read().await;
            let storage = match find_storage_for_path(&st.storages, &dest_path) {
                Some(s) => s,
                None => {
                    err(id, "No storage found for path");
                    return;
                }
            };

            let parent = parent_path(&dest_path);
            let parent_handle = find_dir_handle(storage, parent).await;

            let fname = file_name(&dest_path).to_string();
            let info = NewObjectInfo::file(&fname, size);
            progress(id, 0, Some(size));

            let byte_stream =
                stream::unfold((file, 0_u64), move |(mut file, mut sent)| async move {
                    let mut buffer = vec![0_u8; 1_048_576];
                    match file.read(&mut buffer).await {
                        Ok(0) => None,
                        Ok(read_bytes) => {
                            buffer.truncate(read_bytes);
                            sent += read_bytes as u64;
                            progress(id, sent, Some(size));
                            Some((Ok::<_, std::io::Error>(Bytes::from(buffer)), (file, sent)))
                        }
                        Err(error) => Some((Err(error), (file, sent))),
                    }
                });

            match storage
                .upload(parent_handle, info, Box::pin(byte_stream))
                .await
            {
                Ok(_) => {
                    ok(id, serde_json::json!({"bytes": size, "path": dest_path}));
                }
                Err(e) => err(id, format!("Upload failed: {e}")),
            }
        }

        Request::Mkdir { path, name } => {
            if let Err(e) = ensure_connected(&state).await {
                err(id, e);
                return;
            }
            let st = state.read().await;
            let storage = match find_storage_for_path(&st.storages, &path) {
                Some(s) => s,
                None => {
                    err(id, "No storage found for path");
                    return;
                }
            };

            let parent_handle = find_dir_handle(storage, &path).await;

            match storage.create_folder(parent_handle, &name).await {
                Ok(_) => ok(id, serde_json::json!({"created": name})),
                Err(e) => err(id, format!("mkdir failed: {e}")),
            }
        }

        Request::Delete { path } => {
            if let Err(e) = ensure_connected(&state).await {
                err(id, e);
                return;
            }
            let st = state.read().await;
            let storage = match find_storage_for_path(&st.storages, &path) {
                Some(s) => s,
                None => {
                    err(id, "No storage found for path");
                    return;
                }
            };

            let parent = parent_path(&path);
            let target_name = file_name(&path);

            let handle = match find_object_handle(storage, parent, target_name).await {
                Some(h) => h,
                None => {
                    err(id, format!("Object not found: {path}"));
                    return;
                }
            };

            match storage.delete(handle).await {
                Ok(_) => ok(id, serde_json::json!({"deleted": path})),
                Err(e) => err(id, format!("Delete failed: {e}")),
            }
        }

        Request::Rename { path, new_name } => {
            if let Err(e) = ensure_connected(&state).await {
                err(id, e);
                return;
            }
            let st = state.read().await;
            let storage = match find_storage_for_path(&st.storages, &path) {
                Some(s) => s,
                None => {
                    err(id, "No storage found for path");
                    return;
                }
            };

            let parent = parent_path(&path);
            let target_name = file_name(&path);

            let handle = match find_object_handle(storage, parent, target_name).await {
                Some(h) => h,
                None => {
                    err(id, format!("Object not found: {path}"));
                    return;
                }
            };

            match storage.rename(handle, &new_name).await {
                Ok(_) => ok(id, serde_json::json!({"renamed": new_name})),
                Err(e) => err(id, format!("Rename failed: {e}")),
            }
        }

        Request::DeviceInfo => {
            if let Err(e) = ensure_connected(&state).await {
                err(id, e);
                return;
            }
            let st = state.read().await;
            if let Some(ref device) = st.device {
                let info = device.device_info();
                let data = serde_json::json!({
                    "manufacturer": info.manufacturer,
                    "model": info.model,
                    "serial": info.serial_number,
                    "version": info.device_version,
                });
                ok(id, data);
            } else {
                err(id, "Not connected");
            }
        }
    }
}

async fn find_object_handle(
    storage: &Storage,
    parent_path: &str,
    target_name: &str,
) -> Option<mtp_rs::ptp::ObjectHandle> {
    let parent_handle = find_dir_handle(storage, parent_path).await;
    let objects = storage.list_objects(parent_handle).await.ok()?;
    for obj in objects {
        if obj.filename == target_name {
            return Some(obj.handle);
        }
    }
    None
}

async fn find_dir_handle(storage: &Storage, path: &str) -> Option<mtp_rs::ptp::ObjectHandle> {
    let trimmed = path.trim_start_matches('/');
    let parts: Vec<&str> = trimmed.split('/').collect();

    if parts.is_empty() || (parts.len() == 1 && parts[0].is_empty()) {
        return None;
    }

    // Skip the first component (storage label like "Internal shared storage")
    // since it's not an actual directory on the device.
    let dir_parts: Vec<&str> = parts.iter().skip(1).copied().collect();

    if dir_parts.is_empty() {
        return None;
    }

    let mut current_handle: Option<mtp_rs::ptp::ObjectHandle> = None;
    for part in &dir_parts {
        if part.is_empty() {
            continue;
        }
        let objects = match storage.list_objects(current_handle).await {
            Ok(objs) => objs,
            Err(_) => return None,
        };
        let mut found = None;
        for obj in objects {
            if obj.filename == *part && is_directory(&obj) {
                found = Some(obj.handle);
                break;
            }
        }
        current_handle = found;
        if current_handle.is_none() {
            return None;
        }
    }
    current_handle
}

#[tokio::main]
async fn main() {
    let state = Arc::new(RwLock::new(DaemonState::new()));
    let stdin = io::stdin();
    let reader = io::BufReader::new(stdin);

    ok(
        0,
        serde_json::json!({"ready": true, "version": env!("CARGO_PKG_VERSION")}),
    );

    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };

        if line.trim().is_empty() {
            continue;
        }

        let incoming: IncomingRequest = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                err(0, format!("Invalid request: {e}"));
                continue;
            }
        };

        handle_request(incoming.request, incoming.id, &state).await;
    }
}
