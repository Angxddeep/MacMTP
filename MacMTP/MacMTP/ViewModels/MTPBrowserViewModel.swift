import Foundation
import Combine

@MainActor
class MTPBrowserViewModel: ObservableObject {
    @Published var currentPath: String = "/Internal Storage"
    @Published var files: [FileItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    private var history: [String] = []
    private var historyIndex: Int = -1
    
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }
    
    init() {
        history = ["/Internal Storage"]
        historyIndex = 0
        loadFiles()
    }
    
    func navigateTo(path: String) {
        // Truncate forward history and append new path
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
        isLoading = true
        errorMessage = nil
        
        // Simulate network delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            var items: [FileItem] = []
            
            if currentPath == "/Internal Storage" {
                items = [
                    FileItem(id: "/Internal Storage/DCIM", name: "DCIM", path: "/Internal Storage/DCIM", isDirectory: true, size: 0, dateModified: Date(), fileExtension: ""),
                    FileItem(id: "/Internal Storage/Download", name: "Download", path: "/Internal Storage/Download", isDirectory: true, size: 0, dateModified: Date(), fileExtension: ""),
                    FileItem(id: "/Internal Storage/Music", name: "Music", path: "/Internal Storage/Music", isDirectory: true, size: 0, dateModified: Date(), fileExtension: ""),
                    FileItem(id: "/Internal Storage/Pictures", name: "Pictures", path: "/Internal Storage/Pictures", isDirectory: true, size: 0, dateModified: Date(), fileExtension: "")
                ]
            } else if currentPath == "/Internal Storage/DCIM" {
                items = [
                    FileItem(id: "/Internal Storage/DCIM/Camera", name: "Camera", path: "/Internal Storage/DCIM/Camera", isDirectory: true, size: 0, dateModified: Date(), fileExtension: ""),
                    FileItem(id: "/Internal Storage/DCIM/Screenshots", name: "Screenshots", path: "/Internal Storage/DCIM/Screenshots", isDirectory: true, size: 0, dateModified: Date(), fileExtension: "")
                ]
            } else if currentPath == "/Internal Storage/DCIM/Camera" {
                items = [
                    FileItem(id: "/Internal Storage/DCIM/Camera/IMG_20260401.jpg", name: "IMG_20260401.jpg", path: "/Internal Storage/DCIM/Camera/IMG_20260401.jpg", isDirectory: false, size: 4500000, dateModified: Date(), fileExtension: "jpg"),
                    FileItem(id: "/Internal Storage/DCIM/Camera/VID_20260402.mp4", name: "VID_20260402.mp4", path: "/Internal Storage/DCIM/Camera/VID_20260402.mp4", isDirectory: false, size: 120500000, dateModified: Date(), fileExtension: "mp4")
                ]
            }
            
            self.files = items
            self.isLoading = false
        }
    }
}
