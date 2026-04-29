import SwiftUI

struct FileBrowserPaneView: View {
    let title: String
    let currentPath: String
    let files: [FileItem]
    let isLoading: Bool
    let errorMessage: String?
    
    let onNavigateTo: (String) -> Void
    let onNavigateBack: () -> Void
    let onNavigateForward: () -> Void
    let canGoBack: Bool
    let canGoForward: Bool
    
    @State private var selectedFileIDs = Set<FileItem.ID>()
    @State private var sortOrder = [KeyPathComparator(\FileItem.name)]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Breadcrumb and Navigation
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Exact Image Replica: Custom Dark Liquid Glass Capsule
                    HStack(spacing: 0) {
                        Button(action: onNavigateBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 38, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canGoBack)
                        .foregroundColor(canGoBack ? .white : .white.opacity(0.3))
                        
                        Divider()
                            .frame(width: 1, height: 18)
                            .background(Color.white.opacity(0.15))
                        
                        Button(action: onNavigateForward) { 
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 38, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canGoForward)
                        .foregroundColor(canGoForward ? .white : .white.opacity(0.3))
                    }
                    .background(
                        Capsule()
                            .fill(Color(red: 0.12, green: 0.13, blue: 0.15).opacity(0.85)) // Dark sleek color from image
                    )
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                }
                .padding()
                
                Divider()
                
                // Path Bar (Breadcrumbs)
                HStack {
                    BreadcrumbView(path: currentPath, onNavigateTo: onNavigateTo)
                    Spacer()
                }
                
                Divider()
            }
            .background(.ultraThinMaterial) // THIS provides the true liquid glass background for the header
            
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
                        HStack {
                            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundColor(file.isDirectory ? .blue : .secondary)
                            Text(file.name)
                        }
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
            }
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
                            // Add simple hover effect indication if desired
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
