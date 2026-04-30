import SwiftUI
import UniformTypeIdentifiers

enum FileBrowserLocation: String, Codable, Hashable {
    case local
    case mtp
}

struct FileDragItem: Codable, Hashable, Transferable {
    let name: String
    let path: String
    let handle: UInt32
    let isDirectory: Bool
    let origin: FileBrowserLocation

    init(file: FileItem, origin: FileBrowserLocation) {
        self.name = file.name
        self.path = file.path
        self.handle = file.handle
        self.isDirectory = file.isDirectory
        self.origin = origin
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
