import Foundation

// MARK: - Request Types

enum MTPRequest: Encodable {
    case ping
    case listDevices
    case listStorages
    case listFiles(path: String)
    case download(path: String, dest: String)
    case upload(src: String, destPath: String)
    case mkdir(path: String, name: String)
    case delete(path: String)
    case rename(path: String, newName: String)
    case deviceInfo

    private enum CodingKeys: String, CodingKey {
        case command, id, path, dest, src, destPath, name, newName
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)

        switch self {
        case .ping:
            try container.encode("ping", forKey: DynamicKey(stringValue: "command")!)
        case .listDevices:
            try container.encode("list_devices", forKey: DynamicKey(stringValue: "command")!)
        case .listStorages:
            try container.encode("list_storages", forKey: DynamicKey(stringValue: "command")!)
        case .listFiles(let path):
            try container.encode("list_files", forKey: DynamicKey(stringValue: "command")!)
            try container.encode(path, forKey: DynamicKey(stringValue: "path")!)
        case .download(let path, let dest):
            try container.encode("download", forKey: DynamicKey(stringValue: "command")!)
            try container.encode(path, forKey: DynamicKey(stringValue: "path")!)
            try container.encode(dest, forKey: DynamicKey(stringValue: "dest")!)
        case .upload(let src, let destPath):
            try container.encode("upload", forKey: DynamicKey(stringValue: "command")!)
            try container.encode(src, forKey: DynamicKey(stringValue: "src")!)
            try container.encode(destPath, forKey: DynamicKey(stringValue: "dest_path")!)
        case .mkdir(let path, let name):
            try container.encode("mkdir", forKey: DynamicKey(stringValue: "command")!)
            try container.encode(path, forKey: DynamicKey(stringValue: "path")!)
            try container.encode(name, forKey: DynamicKey(stringValue: "name")!)
        case .delete(let path):
            try container.encode("delete", forKey: DynamicKey(stringValue: "command")!)
            try container.encode(path, forKey: DynamicKey(stringValue: "path")!)
        case .rename(let path, let newName):
            try container.encode("rename", forKey: DynamicKey(stringValue: "command")!)
            try container.encode(path, forKey: DynamicKey(stringValue: "path")!)
            try container.encode(newName, forKey: DynamicKey(stringValue: "new_name")!)
        case .deviceInfo:
            try container.encode("device_info", forKey: DynamicKey(stringValue: "command")!)
        }
    }
}

private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - Response Types

struct MTPResponse: Decodable {
    let id: UInt64
    let status: String
    let data: MTPResponseData?
    let message: String?
}

enum MTPResponseData: Decodable {
    case devices([MTPDeviceEntry])
    case storages([MTPStorageEntry])
    case files([MTPFileEntry])
    case deviceInfo(MTPDeviceInfoEntry)
    case generic([String: AnyCodableValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Empty arrays decode as any array type — treat as empty files list
        if let arr = try? container.decode([AnyCodableValue].self), arr.isEmpty {
            self = .files([])
            return
        }

        if let files = try? container.decode([MTPFileEntry].self) {
            self = .files(files)
            return
        }
        if let devices = try? container.decode([MTPDeviceEntry].self) {
            self = .devices(devices)
            return
        }
        if let storages = try? container.decode([MTPStorageEntry].self) {
            self = .storages(storages)
            return
        }
        if let info = try? container.decode(MTPDeviceInfoEntry.self) {
            self = .deviceInfo(info)
            return
        }
        if let generic = try? container.decode([String: AnyCodableValue].self) {
            self = .generic(generic)
            return
        }

        self = .generic([:])
    }
}

struct MTPDeviceEntry: Codable {
    let name: String
    let serial: String
    let vendor: String
    let product: String
    let locationId: UInt32

    enum CodingKeys: String, CodingKey {
        case name, serial, vendor, product
        case locationId = "location_id"
    }
}

struct MTPStorageEntry: Codable {
    let id: UInt32
    let description: String
    let freeSpace: UInt64
    let totalSpace: UInt64

    enum CodingKeys: String, CodingKey {
        case id, description
        case freeSpace = "free_space"
        case totalSpace = "total_space"
    }
}

struct MTPFileEntry: Codable, Identifiable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let dateModified: String
    let fileExtension: String

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case name, path, size
        case isDirectory = "is_directory"
        case dateModified = "date_modified"
        case fileExtension = "file_extension"
    }
}

struct MTPDeviceInfoEntry: Codable {
    let manufacturer: String?
    let model: String?
    let serial: String?
    let version: String?
}

// MARK: - Flexible JSON value for generic responses

enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([AnyCodableValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: AnyCodableValue].self) { self = .dictionary(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
