import Foundation
import Combine

@MainActor
class LocalBrowserViewModel: ObservableObject {
    @Published var currentPath: String
    @Published var files: [FileItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    private let fileManager = FileManager.default
    private let transferStore = TransferProgressStore.shared
    private var history: [String] = []
    private var historyIndex: Int = -1
    
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }
    
    init(startingPath: String = NSHomeDirectory()) {
        self.currentPath = startingPath
        history = [startingPath]
        historyIndex = 0
        loadFiles()
    }
    
    func navigateTo(path: String) {
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            // Truncate forward history and append new path
            if historyIndex < history.count - 1 {
                history = Array(history.prefix(historyIndex + 1))
            }
            history.append(path)
            historyIndex = history.count - 1
            currentPath = path
            loadFiles()
        }
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
        let parentPath = (currentPath as NSString).deletingLastPathComponent
        if parentPath != currentPath && currentPath != "/" {
            navigateTo(path: parentPath)
        }
    }
    
    func loadFiles() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: currentPath)
                var items: [FileItem] = []
                
                for item in contents {
                    // Skip hidden files
                    if item.hasPrefix(".") { continue }
                    
                    let fullPath = (currentPath as NSString).appendingPathComponent(item)
                    let attributes = try? fileManager.attributesOfItem(atPath: fullPath)
                    
                    let fileType = attributes?[.type] as? FileAttributeType
                    let isDirectory = fileType == .typeDirectory
                    let size = attributes?[.size] as? Int64 ?? 0
                    let dateModified = attributes?[.modificationDate] as? Date ?? Date()
                    let fileExtension = (item as NSString).pathExtension
                    
                    let fileItem = FileItem(
                        id: fullPath,
                        name: item,
                        path: fullPath,
                        handle: 0,
                        storageId: 0,
                        isDirectory: isDirectory,
                        size: size,
                        dateModified: dateModified,
                        fileExtension: fileExtension
                    )
                    items.append(fileItem)
                }
                
                // Sort: Folders first, then alphabetically
                items.sort {
                    if $0.isDirectory == $1.isDirectory {
                        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                    return $0.isDirectory && !$1.isDirectory
                }
                
                self.files = items
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func copyLocalFiles(_ urls: [URL], toDirectory directoryPath: String) async {
        guard !urls.isEmpty else { return }

        do {
            for url in urls {
                let destinationURL = try availableDestinationURL(
                    forName: url.lastPathComponent,
                    inDirectory: directoryPath
                )
                try await copyFileWithProgress(from: url, to: destinationURL)
            }
            errorMessage = nil
            loadFiles()
        } catch {
            errorMessage = "Copy failed: \(error.localizedDescription)"
        }
    }

    func importDraggedItems(
        _ items: [FileDragItem],
        toDirectory directoryPath: String,
        mtpViewModel: MTPBrowserViewModel
    ) async {
        guard !items.isEmpty else { return }

        do {
            for item in items {
                switch item.origin {
                case .local:
                    let sourceURL = URL(fileURLWithPath: item.path)
                    let destinationURL = try availableDestinationURL(
                        forName: sourceURL.lastPathComponent,
                        inDirectory: directoryPath
                    )
                    try await copyFileWithProgress(from: sourceURL, to: destinationURL)
                case .mtp:
                    guard !item.isDirectory else {
                        throw LocalFileTransferError.unsupportedDirectoryTransfer(item.name)
                    }

                    let destinationURL = try availableDestinationURL(
                        forName: item.name,
                        inDirectory: directoryPath
                    )
                    
                    // Create a dummy FileItem from the drag item
                    let mtpFile = FileItem(
                        id: item.path,
                        name: item.name,
                        path: item.path,
                        handle: item.handle,
                        storageId: 0,
                        isDirectory: false,
                        size: 0,
                        dateModified: Date(),
                        fileExtension: (item.name as NSString).pathExtension
                    )
                    
                    try await mtpViewModel.downloadFile(mtpFile, localPath: destinationURL.path)
                }
            }
            errorMessage = nil
            loadFiles()
        } catch {
            errorMessage = "Drop failed: \(error.localizedDescription)"
        }
    }

    private func availableDestinationURL(forName name: String, inDirectory directoryPath: String) throws -> URL {
        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let proposedURL = directoryURL.appendingPathComponent(name)

        guard fileManager.fileExists(atPath: proposedURL.path) else {
            return proposedURL
        }

        let baseName = (name as NSString).deletingPathExtension
        let fileExtension = (name as NSString).pathExtension

        for copyIndex in 1...10_000 {
            let candidateName: String
            if fileExtension.isEmpty {
                candidateName = "\(baseName) copy \(copyIndex)"
            } else {
                candidateName = "\(baseName) copy \(copyIndex).\(fileExtension)"
            }

            let candidateURL = directoryURL.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        throw LocalFileTransferError.noAvailableDestination(name)
    }

    private func copyFileWithProgress(from sourceURL: URL, to destinationURL: URL) async throws {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else {
            throw LocalFileTransferError.unsupportedDirectoryTransfer(sourceURL.lastPathComponent)
        }

        let totalBytes = try fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0
        let jobID = transferStore.startJob(
            title: "Copying \(sourceURL.lastPathComponent)",
            detail: destinationURL.deletingLastPathComponent().path,
            totalBytes: totalBytes
        )

        do {
            try await Task.detached(priority: .userInitiated) {
                let input = try FileHandle(forReadingFrom: sourceURL)
                defer { try? input.close() }

                FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
                let output = try FileHandle(forWritingTo: destinationURL)
                defer { try? output.close() }

                var copiedBytes: Int64 = 0
                while true {
                    try Task.checkCancellation()
                    let data = try input.read(upToCount: 1_048_576) ?? Data()
                    guard !data.isEmpty else { break }
                    try output.write(contentsOf: data)
                    copiedBytes += Int64(data.count)

                    let progressBytes = copiedBytes
                    await MainActor.run {
                        self.transferStore.updateJob(jobID, completedBytes: progressBytes)
                    }
                }
            }.value

            transferStore.finishJob(jobID, detail: destinationURL.path)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            transferStore.failJob(jobID, message: error.localizedDescription)
            throw error
        }
    }
}

private enum LocalFileTransferError: LocalizedError {
    case noAvailableDestination(String)
    case unsupportedDirectoryTransfer(String)

    var errorDescription: String? {
        switch self {
        case .noAvailableDestination(let name):
            return "Could not find an available destination name for \(name)."
        case .unsupportedDirectoryTransfer(let name):
            return "Folder transfer is not supported yet for \(name)."
        }
    }
}
