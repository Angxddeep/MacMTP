import SwiftUI

struct FileBrowserPaneView: View {
    let title: String
    let location: FileBrowserLocation
    let currentPath: String
    let files: [FileItem]
    let isLoading: Bool
    let errorMessage: String?
    
    let onNavigateTo: (String) -> Void
    let onDropLocalFiles: ([URL], String) async -> Void
    let onDropDraggedFiles: ([FileDragItem], String) async -> Void
    
    @State private var selectedFileIDs = Set<FileItem.ID>()
    @State private var sortOrder = [KeyPathComparator(\FileItem.name)]
    @State private var isDropTargeted = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb path bar with Liquid Glass
            BreadcrumbView(path: currentPath, onNavigateTo: onNavigateTo)
                .glassEffect(.regular, in: .rect(cornerRadius: 0))
            
            Divider()
            
            // File Table
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let errorMessage = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            } else {
                Table(files, selection: $selectedFileIDs, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { file in
                        FileNameCell(
                            file: file,
                            location: location,
                            onDropLocalFiles: { urls in
                                await onDropLocalFiles(urls, file.path)
                            },
                            onDropDraggedFiles: { items in
                                await onDropDraggedFiles(items, file.path)
                            }
                        )
                    }
                    TableColumn("Date Modified", value: \.dateModified) { file in
                        Text(file.formattedDate)
                            .foregroundColor(.secondary)
                    }
                    TableColumn("Size", value: \.size) { file in
                        Text(file.formattedSize)
                            .foregroundColor(.secondary)
                    }
                    TableColumn("Kind", value: \.fileExtension) { file in
                        Text(file.isDirectory ? "Folder" : (file.fileExtension.isEmpty ? "Document" : file.fileExtension.uppercased()))
                            .foregroundColor(.secondary)
                    }
                }
                .contextMenu(forSelectionType: FileItem.ID.self) { items in
                    if items.count == 1, let id = items.first, let file = files.first(where: { $0.id == id }) {
                        if file.isDirectory {
                            Button("Open") {
                                onNavigateTo(file.path)
                            }
                        }
                    }
                } primaryAction: { items in
                    if items.count == 1, let id = items.first, let file = files.first(where: { $0.id == id }) {
                        if file.isDirectory {
                            onNavigateTo(file.path)
                        }
                    }
                }
                .dropDestination(for: URL.self, action: { urls, _ in
                    scheduleLocalDrop(urls, toDirectory: currentPath)
                    return true
                }, isTargeted: { isTargeted in
                    isDropTargeted = isTargeted
                })
                .dropDestination(for: FileDragItem.self, action: { items, _ in
                    scheduleDraggedItemDrop(items, toDirectory: currentPath)
                    return true
                }, isTargeted: { isTargeted in
                    isDropTargeted = isTargeted
                })
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.tint, lineWidth: 2)
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func scheduleLocalDrop(_ urls: [URL], toDirectory directoryPath: String) {
        DispatchQueue.main.async {
            Task {
                await onDropLocalFiles(urls, directoryPath)
            }
        }
    }

    private func scheduleDraggedItemDrop(_ items: [FileDragItem], toDirectory directoryPath: String) {
        DispatchQueue.main.async {
            Task {
                await onDropDraggedFiles(items, directoryPath)
            }
        }
    }
}

private struct FileNameCell: View {
    let file: FileItem
    let location: FileBrowserLocation
    let onDropLocalFiles: ([URL]) async -> Void
    let onDropDraggedFiles: ([FileDragItem]) async -> Void

    @State private var isDropTargeted = false

    var body: some View {
        HStack {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(file.isDirectory ? .blue : .secondary)
            Text(file.name)
        }
        .contentShape(Rectangle())
        .draggable(FileDragItem(file: file, origin: location)) {
            Label(file.name, systemImage: file.isDirectory ? "folder.fill" : "doc.fill")
        }
        .modifier(FolderDropTargetModifier(
            isEnabled: file.isDirectory,
            isTargeted: $isDropTargeted,
            onDropLocalFiles: onDropLocalFiles,
            onDropDraggedFiles: onDropDraggedFiles
        ))
        .background {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.tint.opacity(0.14))
            }
        }
    }
}

private struct FolderDropTargetModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    let onDropLocalFiles: ([URL]) async -> Void
    let onDropDraggedFiles: ([FileDragItem]) async -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .dropDestination(for: URL.self, action: { urls, _ in
                    DispatchQueue.main.async {
                        Task {
                            await onDropLocalFiles(urls)
                        }
                    }
                    return true
                }, isTargeted: { isDropTargeted in
                    isTargeted = isDropTargeted
                })
                .dropDestination(for: FileDragItem.self, action: { items, _ in
                    DispatchQueue.main.async {
                        Task {
                            await onDropDraggedFiles(items)
                        }
                    }
                    return true
                }, isTargeted: { isDropTargeted in
                    isTargeted = isDropTargeted
                })
        } else {
            content
        }
    }
}

struct BreadcrumbView: View {
    let path: String
    let onNavigateTo: (String) -> Void
    
    var breadcrumbs: [(name: String, path: String)] {
        var components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        var result: [(name: String, path: String)] = []
        
        let isMTP = path.hasPrefix("/Internal Storage")
        if isMTP {
            result.append((name: "Internal Storage", path: "/Internal Storage"))
            if let first = components.first, first == "Internal Storage" {
                components.removeFirst()
            }
        } else {
            result.append((name: "Mac", path: "/"))
        }
        
        var currentAccumulatedPath = isMTP ? "/Internal Storage" : ""
        
        for component in components {
            if currentAccumulatedPath == "/" || currentAccumulatedPath.isEmpty {
                currentAccumulatedPath = "/\(component)"
            } else {
                currentAccumulatedPath += "/\(component)"
            }
            result.append((name: component, path: currentAccumulatedPath))
        }
        
        return result
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                    Button(action: {
                        onNavigateTo(crumb.path)
                    }) {
                        Text(crumb.name)
                            .font(.subheadline)
                            .foregroundColor(index == breadcrumbs.count - 1 ? .primary : .blue)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        if index < breadcrumbs.count - 1 {
                            NSCursor.pointingHand.set()
                        }
                    }
                    
                    if index < breadcrumbs.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
