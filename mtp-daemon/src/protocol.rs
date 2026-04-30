use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct IncomingRequest {
    pub id: u64,
    #[serde(flatten)]
    pub request: Request,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "command")]
pub enum Request {
    #[serde(rename = "list_devices")]
    ListDevices,
    #[serde(rename = "list_storages")]
    ListStorages,
    #[serde(rename = "list_files")]
    ListFiles {
        path: String,
        handle: Option<u32>,
        storage_id: Option<u32>,
    },
    #[serde(rename = "download")]
    Download {
        path: String,
        dest: String,
        handle: Option<u32>,
    },
    #[serde(rename = "upload")]
    Upload {
        src: String,
        dest_path: String,
        parent_handle: Option<u32>,
    },
    #[serde(rename = "mkdir")]
    Mkdir {
        path: String,
        name: String,
        parent_handle: Option<u32>,
    },
    #[serde(rename = "delete")]
    Delete { path: String, handle: Option<u32> },
    #[serde(rename = "rename")]
    Rename {
        path: String,
        new_name: String,
        handle: Option<u32>,
    },
    #[serde(rename = "device_info")]
    DeviceInfo,
    #[serde(rename = "ping")]
    Ping,
}

#[derive(Debug, Serialize)]
pub struct Response {
    pub id: u64,
    #[serde(flatten)]
    pub status: ResponseStatus,
}

#[derive(Debug, Serialize)]
#[serde(tag = "event_type")]
pub enum MtpEvent {
    #[serde(rename = "ObjectAdded")]
    ObjectAdded { handle: u32 },
    #[serde(rename = "ObjectRemoved")]
    ObjectRemoved { handle: u32 },
    #[serde(rename = "StoreAdded")]
    StoreAdded { storage_id: u32 },
    #[serde(rename = "StoreRemoved")]
    StoreRemoved { storage_id: u32 },
    #[serde(rename = "StorageInfoChanged")]
    StorageInfoChanged { storage_id: u32 },
    #[serde(rename = "ObjectInfoChanged")]
    ObjectInfoChanged { handle: u32 },
    #[serde(rename = "DeviceInfoChanged")]
    DeviceInfoChanged,
    #[serde(rename = "DeviceReset")]
    DeviceReset,
    #[serde(rename = "Disconnected")]
    Disconnected,
    #[serde(rename = "Unknown")]
    Unknown { code: u16, params: Vec<u32> },
}

#[derive(Debug, Serialize)]
#[serde(tag = "status")]
pub enum ResponseStatus {
    #[serde(rename = "ok")]
    Ok { data: serde_json::Value },
    #[serde(rename = "progress")]
    Progress { data: serde_json::Value },
    #[serde(rename = "error")]
    Error { message: String },
    #[serde(rename = "event")]
    Event(MtpEvent),
}

#[derive(Debug, Serialize, Clone)]
pub struct DeviceEntry {
    pub name: String,
    pub serial: String,
    pub vendor: String,
    pub product: String,
    pub location_id: u32,
}

#[derive(Debug, Serialize, Clone)]
pub struct StorageEntry {
    pub id: u32,
    pub description: String,
    pub free_space: u64,
    pub total_space: u64,
}

#[derive(Debug, Serialize, Clone)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub size: u64,
    pub date_modified: String,
    pub file_extension: String,
    pub handle: u32,
    pub storage_id: u32,
}
