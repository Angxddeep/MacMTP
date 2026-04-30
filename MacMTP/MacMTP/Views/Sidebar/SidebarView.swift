import SwiftUI
import AppKit

struct SidebarView: View {
    let favorites: [FavoriteLocation]
    @Binding var selectedDestination: SidebarDestination?
    let onAddFavorite: () -> Void
    let onDropLocalFilesToFavorite: ([URL], FavoriteLocation) async -> Void
    let onDropDraggedFilesToFavorite: ([FileDragItem], FavoriteLocation) async -> Void
    let onDropLocalFilesToPhone: ([URL]) async -> Void
    let onDropDraggedFilesToPhone: ([FileDragItem]) async -> Void

    var body: some View {
        List(selection: $selectedDestination) {
            Section("Favourites") {
                ForEach(favorites) { favorite in
                    SidebarIconLabel(favorite.name, icon: .system("macbook", accessibilityLabel: "Mac"))
                        .tag(SidebarDestination.favorite(favorite.path))
                        .modifier(SidebarDropTargetModifier(
                            onDropLocalFiles: { urls in
                                await onDropLocalFilesToFavorite(urls, favorite)
                            },
                            onDropDraggedFiles: { items in
                                await onDropDraggedFilesToFavorite(items, favorite)
                            }
                        ))
                }

                Button(action: onAddFavorite) {
                    Label("Add Favorite", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Section("Devices") {
                SidebarIconLabel("Phone", icon: .android)
                    .tag(SidebarDestination.phone)
                    .modifier(SidebarDropTargetModifier(
                        onDropLocalFiles: onDropLocalFilesToPhone,
                        onDropDraggedFiles: onDropDraggedFilesToPhone
                    ))
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Locations")
    }
}

private struct SidebarDropTargetModifier: ViewModifier {
    let onDropLocalFiles: ([URL]) async -> Void
    let onDropDraggedFiles: ([FileDragItem]) async -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
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
            .background {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.tint.opacity(0.14))
                }
            }
    }
}

struct SidebarIconLabel: View {
    let title: String
    let icon: SidebarIconAsset

    init(_ title: String, icon: SidebarIconAsset) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SidebarSVGIcon(icon)
        }
    }
}

struct SidebarSVGIcon: View {
    let icon: SidebarIconAsset

    init(_ icon: SidebarIconAsset) {
        self.icon = icon
    }

    var body: some View {
        Group {
            if case let .system(systemName, _) = icon {
                Image(systemName: systemName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            } else if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSystemImage)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 17, height: 17)
        .accessibilityLabel(icon.accessibilityLabel)
    }

    private var image: NSImage? {
        switch icon {
        case .system:
            return nil
        case .android:
            return SidebarSVGImageCache.image(named: icon.resourceName)
        }
    }

    private var fallbackSystemImage: String {
        switch icon {
        case let .system(systemName, _):
            return systemName
        case .android:
            return "smartphone"
        }
    }
}

enum SidebarSVGImageCache {
    private static var images: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let cachedImage = images[name] {
            return cachedImage
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "svg")
            ?? Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Resources/SVGs"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        images[name] = image
        return image
    }
}
