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
    ListFiles { path: String },
    #[serde(rename = "download")]
    Download { path: String, dest: String },
    #[serde(rename = "upload")]
    Upload { src: String, dest_path: String },
    #[serde(rename = "mkdir")]
    Mkdir { path: String, name: String },
    #[serde(rename = "delete")]
    Delete { path: String },
    #[serde(rename = "rename")]
    Rename { path: String, new_name: String },
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
#[serde(tag = "status")]
pub enum ResponseStatus {
    #[serde(rename = "ok")]
    Ok { data: serde_json::Value },
    #[serde(rename = "progress")]
    Progress { data: serde_json::Value },
    #[serde(rename = "error")]
    Error { message: String },
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
}
