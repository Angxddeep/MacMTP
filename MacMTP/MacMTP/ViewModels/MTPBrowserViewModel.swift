import Foundation
import Combine

@MainActor
class MTPBrowserViewModel: ObservableObject {
    @Published var currentPath: String = "/Internal Storage"
    @Published var currentHandle: UInt32? = nil
    @Published var currentStorageId: UInt32? = nil
    @Published var files: [FileItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var isConnected = false

    private struct NavigationState: Equatable {
        let path: String
        let handle: UInt32?
        let storageId: UInt32?
    }

    private var history: [NavigationState] = []
    private var historyIndex: Int = -1
    private let bridge = MTPBridge()
    private let transferStore = TransferProgressStore.shared
    private var hasConnected = false

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    init() {
        let initial = NavigationState(path: "/Internal Storage", handle: nil, storageId: nil)
        history = [initial]
        historyIndex = 0
    }

    /// Connect to the MTP daemon and load initial files.
    func connect() async {
        guard !hasConnected else { return }
        hasConnected = true

        do {
            try await bridge.connect()
            isConnected = true
            startEventListening()
            loadFiles()
        } catch {
            errorMessage = "Failed to connect to MTP daemon: \(error.localizedDescription)"
        }
    }

    private func startEventListening() {
        Task {
            for await event in bridge.events {
                handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: MTPEvent) {
        switch event {
        case .objectAdded, .objectRemoved, .objectInfoChanged, .storeAdded, .storeRemoved, .storageInfoChanged:
            // For now, just refresh the current view
            loadFiles()
        case .deviceReset, .disconnected:
            isConnected = false
            hasConnected = false
            errorMessage = "Device disconnected"
            files = []
        case .deviceInfoChanged:
            break
        case .unknown:
            break
        }
    }

    func disconnect() {
        bridge.disconnect()
        isConnected = false
        hasConnected = false
    }

    func navigateTo(path: String, handle: UInt32? = nil, storageId: UInt32? = nil) {
        if historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }
        let state = NavigationState(path: path, handle: handle, storageId: storageId)
        history.append(state)
        historyIndex = history.count - 1
        
        currentPath = path
        currentHandle = handle
        currentStorageId = storageId
        
        loadFiles()
    }

    func navigateBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        let state = history[historyIndex]
        currentPath = state.path
        currentHandle = state.handle
        currentStorageId = state.storageId
        loadFiles()
    }

    func navigateForward() {
        guard canGoForward else { return }
        historyIndex += 1
        let state = history[historyIndex]
        currentPath = state.path
        currentHandle = state.handle
        currentStorageId = state.storageId
        loadFiles()
    }

    func navigateUp() {
        if currentPath != "/Internal Storage" && currentPath != "/" {
            // Finding parent handle is hard without a full tree, 
            // so we fallback to path-based navigation for "Up"
            let parentPath = (currentPath as NSString).deletingLastPathComponent
            navigateTo(path: parentPath.isEmpty ? "/" : parentPath)
        }
    }

    func loadFiles() {
        guard isConnected else {
            // Try to connect first
            Task { await connect() }
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let entries = try await bridge.listFiles(path: currentPath, handle: currentHandle, storageId: currentStorageId)
                let items = entries.map { entry -> FileItem in
                    let date = Self.parseDate(entry.dateModified)
                    return FileItem(
                        id: entry.path,
                        name: entry.name,
                        path: entry.path,
                        handle: entry.handle,
                        storageId: entry.storageId,
                        isDirectory: entry.isDirectory,
                        size: Int64(entry.size),
                        dateModified: date,
                        fileExtension: entry.fileExtension
                    )
                }
                self.files = items
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.files = []
            }
        }
    }

    /// Download a file from the MTP device to a local path.
    func downloadFile(_ item: FileItem, localPath: String) async throws {
        let jobID = transferStore.startJob(
            title: "Downloading \(item.name)",
            detail: localPath,
            totalBytes: item.size
        )

        do {
            _ = try await bridge.download(path: item.path, handle: item.handle, to: localPath) { progress in
                Task { @MainActor in
                    self.transferStore.updateJob(jobID, completedBytes: progress.bytes)
                }
            }
            transferStore.finishJob(jobID, detail: localPath)
        } catch {
            transferStore.failJob(jobID, message: error.localizedDescription)
            throw error
        }
    }

    /// Upload a local file to the MTP device.
    func uploadFile(localPath: String, devicePath: String) async throws {
        try await uploadFileWithProgress(localPath: localPath, devicePath: devicePath)
        loadFiles()
    }

    func uploadLocalFiles(_ urls: [URL], toDirectory directoryPath: String) async {
        guard !urls.isEmpty else { return }

        do {
            for url in urls {
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                guard !isDirectory.boolValue else {
                    throw MTPFileTransferError.unsupportedDirectoryTransfer(url.lastPathComponent)
                }

                let destinationPath = Self.joinPath(directoryPath, url.lastPathComponent)
                try await uploadFileWithProgress(localPath: url.path, devicePath: destinationPath)
            }
            errorMessage = nil
            loadFiles()
        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
        }
    }

    func importDraggedItems(_ items: [FileDragItem], toDirectory directoryPath: String) async {
        guard !items.isEmpty else { return }

        do {
            for item in items {
                switch item.origin {
                case .local:
                    guard !item.isDirectory else {
                        throw MTPFileTransferError.unsupportedDirectoryTransfer(item.name)
                    }

                    let destinationPath = Self.joinPath(directoryPath, item.name)
                    try await uploadFileWithProgress(localPath: item.path, devicePath: destinationPath)
                case .mtp:
                    throw MTPFileTransferError.sameDeviceMoveNotSupported
                }
            }
            errorMessage = nil
            loadFiles()
        } catch {
            errorMessage = "Drop failed: \(error.localizedDescription)"
        }
    }

    /// Create a directory on the MTP device.
    func createDirectory(name: String) async throws {
        try await bridge.mkdir(parentPath: currentPath, name: name, parentHandle: currentHandle)
        loadFiles()
    }

    /// Delete a file or folder on the MTP device.
    func deleteItem(_ item: FileItem) async throws {
        try await bridge.delete(path: item.path, handle: item.handle)
        loadFiles()
    }

    /// Rename a file or folder on the MTP device.
    func renameItem(_ item: FileItem, newName: String) async throws {
        try await bridge.rename(path: item.path, newName: newName, handle: item.handle)
        loadFiles()
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let mtpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter
    }()

    private static func parseDate(_ string: String) -> Date {
        if string.isEmpty { return Date() }
        if let date = iso8601Formatter.date(from: string) { return date }
        if let date = mtpDateFormatter.date(from: string) { return date }
        return Date()
    }

    private static func joinPath(_ directoryPath: String, _ name: String) -> String {
        if directoryPath.hasSuffix("/") {
            return "\(directoryPath)\(name)"
        }
        return "\(directoryPath)/\(name)"
    }

    private func uploadFileWithProgress(localPath: String, devicePath: String) async throws {
        let name = (localPath as NSString).lastPathComponent
        let totalBytes = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64) ?? 0
        let jobID = transferStore.startJob(
            title: "Uploading \(name)",
            detail: devicePath,
            totalBytes: totalBytes
        )

        do {
            _ = try await bridge.upload(localPath: localPath, to: devicePath, parentHandle: currentHandle) { progress in
                Task { @MainActor in
                    self.transferStore.updateJob(jobID, completedBytes: progress.bytes)
                }
            }
            transferStore.finishJob(jobID, detail: devicePath)
        } catch {
            transferStore.failJob(jobID, message: error.localizedDescription)
            throw error
        }
    }
}

private enum MTPFileTransferError: LocalizedError {
    case sameDeviceMoveNotSupported
    case unsupportedDirectoryTransfer(String)

    var errorDescription: String? {
        switch self {
        case .sameDeviceMoveNotSupported:
            return "Moving files inside the phone is not supported yet."
        case .unsupportedDirectoryTransfer(let name):
            return "Folder transfer is not supported yet for \(name)."
        }
    }
}
