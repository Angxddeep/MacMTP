import Foundation

struct FavoriteLocation: Identifiable, Hashable, Codable {
    let name: String
    let path: String

    var id: String { path }

    static var defaultFavorites: [FavoriteLocation] {
        let fileManager = FileManager.default
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first

        return [downloads, documents]
            .compactMap { url in
                guard let url else { return nil }
                return FavoriteLocation(
                    name: fileManager.displayName(atPath: url.path),
                    path: url.path
                )
            }
    }
}

enum SidebarDestination: Hashable {
    case favorite(String)
    case phone
}

enum SidebarIconAsset {
    case system(String, accessibilityLabel: String)
    case android

    var resourceName: String {
        switch self {
        case .system:
            return ""
        case .android:
            return "Android"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case let .system(_, accessibilityLabel):
            return accessibilityLabel
        case .android:
            return "Android"
        }
    }
}
