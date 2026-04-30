import Foundation

/// Manages the mtp-daemon subprocess and handles JSON IPC over stdin/stdout.
final class MTPProcess: @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let lifecycleLock = NSLock()
    private var didLaunch = false
    private var didStop = false

    private struct PendingRequest {
        let continuation: CheckedContinuation<MTPResponse, Error>
        let timeoutTask: Task<Void, Never>?
        let progressHandler: (@Sendable (MTPProgressEntry) -> Void)?
    }

    private var pendingRequests: [UInt64: PendingRequest] = [:]
    private var nextId: UInt64 = 1
    private let lock = NSLock()

    private var buffer = Data()
    private let bufferLock = NSLock()

    /// Path to the mtp-daemon binary. Set this before calling `start()`.
    static var binaryPath: String?

    /// Per-request timeout in seconds.
    static let requestTimeout: TimeInterval = 30

    var isRunning: Bool {
        lifecycleLock.withLock {
            didLaunch && !didStop && process.isRunning
        }
    }

    /// Kill any existing mtp-daemon processes that may be holding USB devices.
    static func killExistingDaemons() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["mtp-daemon"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        // Give time for USB interfaces to be released
        Thread.sleep(forTimeInterval: 0.5)
    }

    deinit {
        stop()
    }

    func start() throws {
        guard let path = MTPProcess.binaryPath else {
            throw MTPError.daemonNotFound("mtp-daemon binary path not set")
        }

        guard FileManager.default.fileExists(atPath: path) else {
            throw MTPError.daemonNotFound("mtp-daemon not found at: \(path)")
        }

        // Kill any existing daemon that may be holding the USB device
        MTPProcess.killExistingDaemons()

        process.executableURL = URL(fileURLWithPath: path)
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Read stdout in background
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.processOutput(data)
        }

        // Log stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                fputs("[mtp-daemon stderr] \(str)\n", Darwin.stderr)
            }
        }

        do {
            try process.run()
            lifecycleLock.withLock {
                didLaunch = true
                didStop = false
            }
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        // Wait for the ready message
        // The daemon sends a ready message on startup
    }

    func stop() {
        let shouldTerminate = lifecycleLock.withLock {
            guard !didStop else { return false }
            didStop = true
            return didLaunch && process.isRunning
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if shouldTerminate {
            process.terminate()
        }

        stdinPipe.fileHandleForWriting.closeFile()

        // Fail all pending requests so callers aren't left hanging
        lock.lock()
        let allPending = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()

        for (_, pending) in allPending {
            pending.timeoutTask?.cancel()
            pending.continuation.resume(throwing: MTPError.notConnected)
        }
    }

    func send(
        _ request: MTPRequest,
        timeout: TimeInterval? = MTPProcess.requestTimeout,
        onProgress: (@Sendable (MTPProgressEntry) -> Void)? = nil
    ) async throws -> MTPResponse {
        guard isRunning else {
            throw MTPError.notConnected
        }

        let id = lock.withLock {
            let id = nextId
            nextId += 1
            return id
        }

        let response: MTPResponse = try await withCheckedThrowingContinuation { continuation in
            let timeoutTask: Task<Void, Never>?
            if let timeout = timeout {
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    self?.timeoutRequest(id: id)
                }
            } else {
                timeoutTask = nil
            }

            lock.withLock {
                pendingRequests[id] = PendingRequest(
                    continuation: continuation,
                    timeoutTask: timeoutTask,
                    progressHandler: onProgress
                )
            }

            do {
                var payload = try JSONEncoder().encode(RequestWrapper(id: id, request: request))
                payload.append(UInt8(ascii: "\n"))
                stdinPipe.fileHandleForWriting.write(payload)
            } catch {
                // Encoding failed — clean up and resume the continuation with the error
                lock.lock()
                let pending = pendingRequests.removeValue(forKey: id)
                lock.unlock()
                pending?.timeoutTask?.cancel()
                continuation.resume(throwing: error)
            }
        }

        return response
    }

    private func timeoutRequest(id: UInt64) {
        lock.lock()
        let pending = pendingRequests.removeValue(forKey: id)
        lock.unlock()

        if let pending = pending {
            pending.continuation.resume(throwing: MTPError.requestTimedOut)
        }
    }

    private func processOutput(_ data: Data) {
        bufferLock.lock()
        buffer.append(data)
        bufferLock.unlock()

        // Process complete lines
        while true {
            bufferLock.lock()
            guard let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) else {
                bufferLock.unlock()
                break
            }

            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])
            bufferLock.unlock()

            guard !lineData.isEmpty else { continue }

            do {
                let response = try JSONDecoder().decode(MTPResponse.self, from: lineData)
                let id = response.id

                if response.status == "progress" {
                    if let progress = response.progressEntry {
                        lock.lock()
                        let handler = pendingRequests[id]?.progressHandler
                        lock.unlock()
                        handler?(progress)
                    }
                    continue
                }

                lock.lock()
                let pending = pendingRequests.removeValue(forKey: id)
                lock.unlock()

                if let pending = pending {
                    pending.timeoutTask?.cancel()
                    pending.continuation.resume(returning: response)
                }
            } catch {
                fputs("[mtp-daemon] Failed to decode response: \(error)\n", Darwin.stderr)
                if let str = String(data: lineData, encoding: .utf8) {
                    fputs("[mtp-daemon] Raw line: \(str)\n", Darwin.stderr)
                }
            }
        }
    }
}

// MARK: - Request Wrapper (matches Rust's expected JSON format)

private struct RequestWrapper: Encodable {
    let id: UInt64
    let command: String
    let extra: [String: AnyEncodableValue]

    init(id: UInt64, request: MTPRequest) {
        self.id = id
        switch request {
        case .ping:
            self.command = "ping"
            self.extra = [:]
        case .listDevices:
            self.command = "list_devices"
            self.extra = [:]
        case .listStorages:
            self.command = "list_storages"
            self.extra = [:]
        case .listFiles(let path):
            self.command = "list_files"
            self.extra = ["path": .string(path)]
        case .download(let path, let dest):
            self.command = "download"
            self.extra = ["path": .string(path), "dest": .string(dest)]
        case .upload(let src, let destPath):
            self.command = "upload"
            self.extra = ["src": .string(src), "dest_path": .string(destPath)]
        case .mkdir(let path, let name):
            self.command = "mkdir"
            self.extra = ["path": .string(path), "name": .string(name)]
        case .delete(let path):
            self.command = "delete"
            self.extra = ["path": .string(path)]
        case .rename(let path, let newName):
            self.command = "rename"
            self.extra = ["path": .string(path), "new_name": .string(newName)]
        case .deviceInfo:
            self.command = "device_info"
            self.extra = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(id, forKey: DynamicKey(stringValue: "id")!)
        try container.encode(command, forKey: DynamicKey(stringValue: "command")!)
        for (key, value) in extra {
            try container.encode(value, forKey: DynamicKey(stringValue: key)!)
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

private enum AnyEncodableValue: Encodable {
    case string(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        }
    }
}

private extension MTPResponse {
    var progressEntry: MTPProgressEntry? {
        guard case .generic(let data) = data,
              case .int(let bytes)? = data["bytes"]
        else {
            return nil
        }

        let total: Int64?
        if case .int(let value)? = data["total"] {
            total = Int64(value)
        } else {
            total = nil
        }

        return MTPProgressEntry(bytes: Int64(bytes), total: total)
    }
}

// MARK: - Errors

enum MTPError: LocalizedError {
    case daemonNotFound(String)
    case notConnected
    case requestFailed(String)
    case requestTimedOut
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .daemonNotFound(let msg): return "Daemon not found: \(msg)"
        case .notConnected: return "No MTP device connected"
        case .requestFailed(let msg): return "Request failed: \(msg)"
        case .requestTimedOut: return "Request timed out — the MTP device may be unresponsive"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        }
    }
}
