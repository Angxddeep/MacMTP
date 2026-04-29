import Foundation
import Combine

@MainActor
class MTPBrowserViewModel: ObservableObject {
    @Published var currentPath: String = "/Internal Storage"
    @Published var files: [FileItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var isConnected = false

    private var history: [String] = []
    private var historyIndex: Int = -1
    private let bridge = MTPBridge()
    private var hasConnected = false

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    init() {
        history = ["/Internal Storage"]
        historyIndex = 0
    }

    /// Connect to the MTP daemon and load initial files.
    func connect() async {
        guard !hasConnected else { return }
        hasConnected = true

        do {
            try await bridge.connect()
            isConnected = true
            loadFiles()
        } catch {
            errorMessage = "Failed to connect to MTP daemon: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        bridge.disconnect()
        isConnected = false
        hasConnected = false
    }

    func navigateTo(path: String) {
        if historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }
        history.append(path)
        historyIndex = history.count - 1
        currentPath = path
        loadFiles()
    }

    func navigateBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        currentPath = history[historyIndex]
        loadFiles()
    }

    func navigateForward() {
        guard canGoForward else { return }
        historyIndex += 1
        currentPath = history[historyIndex]
        loadFiles()
    }

    func navigateUp() {
        if currentPath != "/Internal Storage" && currentPath != "/" {
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
                let entries = try await bridge.listFiles(path: currentPath)
                let items = entries.map { entry -> FileItem in
                    let date = Self.parseDate(entry.dateModified)
                    return FileItem(
                        id: entry.path,
                        name: entry.name,
                        path: entry.path,
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
    func downloadFile(devicePath: String, localPath: String) async throws {
        _ = try await bridge.download(path: devicePath, to: localPath)
    }

    /// Upload a local file to the MTP device.
    func uploadFile(localPath: String, devicePath: String) async throws {
        _ = try await bridge.upload(localPath: localPath, to: devicePath)
        loadFiles()
    }

    /// Create a directory on the MTP device.
    func createDirectory(name: String) async throws {
        try await bridge.mkdir(parentPath: currentPath, name: name)
        loadFiles()
    }

    /// Delete a file or folder on the MTP device.
    func deleteItem(path: String) async throws {
        try await bridge.delete(path: path)
        loadFiles()
    }

    /// Rename a file or folder on the MTP device.
    func renameItem(path: String, newName: String) async throws {
        try await bridge.rename(path: path, newName: newName)
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
}
