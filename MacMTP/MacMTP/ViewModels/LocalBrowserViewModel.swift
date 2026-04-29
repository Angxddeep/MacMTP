import Foundation
import Combine

@MainActor
class LocalBrowserViewModel: ObservableObject {
    @Published var currentPath: String
    @Published var files: [FileItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    private let fileManager = FileManager.default
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
}
