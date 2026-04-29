import Foundation

struct FileItem: Identifiable, Hashable {
    let id: String // Use path as unique identifier
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let dateModified: Date
    let fileExtension: String
    
    var formattedSize: String {
        guard !isDirectory else { return "--" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateModified)
    }
}
