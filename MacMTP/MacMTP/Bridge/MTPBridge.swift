import Foundation

/// Public API for communicating with an MTP device via the mtp-daemon subprocess.
///
/// Usage:
/// ```swift
/// let bridge = MTPBridge()
/// MTPBridge.daemonPath = "/path/to/mtp-daemon"
/// try await bridge.connect()
/// let files = try await bridge.listFiles(path: "/Internal Storage")
/// ```
final class MTPBridge: @unchecked Sendable {
    private let process = MTPProcess()

    /// Set this to the path of the compiled mtp-daemon binary before using.
    static var daemonPath: String? {
        get { MTPProcess.binaryPath }
        set { MTPProcess.binaryPath = newValue }
    }

    init() {}

    /// Start the daemon subprocess.
    func connect() async throws {
        try process.start()

        // Wait a moment for the daemon to send its ready message
        try await Task.sleep(nanoseconds: 200_000_000)

        // Ping to verify connection
        let response = try await send(.ping)
        guard response.status == "ok" else {
            throw MTPError.requestFailed(response.message ?? "ping failed")
        }
    }

    /// Stop the daemon subprocess.
    func disconnect() {
        process.stop()
    }

    /// List all MTP devices connected via USB.
    func listDevices() async throws -> [MTPDeviceEntry] {
        let response = try await send(.listDevices)
        guard response.status == "ok" else {
            throw MTPError.requestFailed(response.message ?? "list_devices failed")
        }
        if case .devices(let devices) = response.data {
            return devices
        }
        throw MTPError.decodingError("Expected devices array")
    }

    /// List storage volumes on the connected device.
    func listStorages() async throws -> [MTPStorageEntry] {
        let response = try await send(.listStorages)
        guard response.status == "ok" else {
            throw MTPError.requestFailed(response.message ?? "list_storages failed")
        }
        if case .storages(let storages) = response.data {
            return storages
        }
        throw MTPError.decodingError("Expected storages array")
    }

    /// List files and folders at the given MTP path.
    ///
    /// Paths look like: `/Internal Storage/DCIM/Camera`
    func listFiles(path: String) async throws -> [MTPFileEntry] {
        let response = try await send(.listFiles(path: path))
        guard response.status == "ok" else {
            throw MTPError.requestFailed(response.message ?? "list_files failed")
        }
        if case .files(let files) = response.data {
            return files
        }
        throw MTPError.decodingError("Expected files array")
    }

    /// Download a file from the MTP device to a local destination.
    func download(path: String, to localDest: String) async throws -> Int {
        let response = try await send(.download(path: path, dest: localDest))
        guard response.status == "ok" else {
            throw MTPError.requestFailed(response.message ?? "download failed")
        }
        if case .generic(let dict) = response.data,
           case .int(let bytes) = dict["bytes"] {
            return bytes
        }
        return 0
    }

    /// Upload a local file to the MTP device.
    func upload(localPath: String, to devicePath: String) async throws -> Int {
        let response = try await send(.upload(src: localPath, destPath: devicePath))
        guard response.status == "ok" else {
            throw MTPError.requestFailed(response.message ?? "upload failed")
        }
        if case .generic(let dict) = response.data,
           case .int(let bytes) = dict["bytes"] {
            return bytes
        }
        return 0
    }

    /// Create a directory on the MTP device.
    func mkdir(parentPath: String, name: String) async throws {
        let response = try await send(.mkdir(path: parentPath, name: name))
        guard response.status == "ok" else {
            throw MTPError.requestFailed(response.message ?? "mkdir failed")
        }
    }

    /// Delete a file or folder on the MTP device.
    func delete(path: String) async throws {
        let response = try await send(.delete(path: path))
        guard response.status == "ok" else {
            throw MTPError.requestFailed(response.message ?? "delete failed")
        }
    }

    /// Rename a file or folder on the MTP device.
    func rename(path: String, newName: String) async throws {
        let response = try await send(.rename(path: path, newName: newName))
        guard response.status == "ok" else {
            throw MTPError.requestFailed(response.message ?? "rename failed")
        }
    }

    /// Get information about the connected device.
    func deviceInfo() async throws -> MTPDeviceInfoEntry {
        let response = try await send(.deviceInfo)
        guard response.status == "ok" else {
            throw MTPError.requestFailed(response.message ?? "device_info failed")
        }
        if case .deviceInfo(let info) = response.data {
            return info
        }
        throw MTPError.decodingError("Expected device info")
    }

    // MARK: - Private

    @discardableResult
    private func send(_ request: MTPRequest) async throws -> MTPResponse {
        try await process.send(request)
    }
}
