import AppKit
import Combine
import SwiftUI

@MainActor
final class TransferProgressStore: ObservableObject {
    static let shared = TransferProgressStore()

    @Published private(set) var jobs: [TransferJob] = []

    private init() {}

    @discardableResult
    func startJob(title: String, detail: String, totalBytes: Int64?) -> UUID {
        let job = TransferJob(title: title, detail: detail, totalBytes: totalBytes)
        jobs.insert(job, at: 0)
        TransferProgressWindowPresenter.show(store: self)
        return job.id
    }

    func updateJob(_ id: UUID, completedBytes: Int64, detail: String? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].completedBytes = completedBytes
        if let detail {
            jobs[index].detail = detail
        }
    }

    func finishJob(_ id: UUID, detail: String? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if let totalBytes = jobs[index].totalBytes {
            jobs[index].completedBytes = totalBytes
        }
        if let detail {
            jobs[index].detail = detail
        }
        jobs[index].status = .finished
    }

    func failJob(_ id: UUID, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = .failed
        jobs[index].detail = message
    }

    func clearFinished() {
        jobs.removeAll { $0.status != .running }
    }
}

struct TransferJob: Identifiable, Equatable {
    enum Status: Equatable {
        case running
        case finished
        case failed
    }

    let id = UUID()
    let title: String
    var detail: String
    let totalBytes: Int64?
    var completedBytes: Int64 = 0
    var status: Status = .running

    var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }

    var progressText: String {
        switch status {
        case .running:
            guard let totalBytes else { return "In progress" }
            return "\(Self.byteFormatter.string(fromByteCount: completedBytes)) of \(Self.byteFormatter.string(fromByteCount: totalBytes))"
        case .finished:
            return "Finished"
        case .failed:
            return "Failed"
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()
}

struct TransferProgressWindow: View {
    @ObservedObject var store: TransferProgressStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Transfers")
                    .font(.headline)

                Spacer()

                Button("Clear Finished") {
                    store.clearFinished()
                }
                .disabled(!store.jobs.contains { $0.status != .running })
            }
            .padding()

            Divider()

            if store.jobs.isEmpty {
                ContentUnavailableView("No Transfers", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.jobs) { job in
                    TransferJobRow(job: job)
                        .padding(.vertical, 6)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 460, height: 320)
    }
}

private struct TransferJobRow: View {
    let job: TransferJob

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(job.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let fraction = job.fractionCompleted {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }

                Text(job.progressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconName: String {
        switch job.status {
        case .running:
            return "arrow.left.arrow.right"
        case .finished:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch job.status {
        case .running:
            return .accentColor
        case .finished:
            return .green
        case .failed:
            return .red
        }
    }
}

@MainActor
private enum TransferProgressWindowPresenter {
    private static var window: NSWindow?

    static func show(store: TransferProgressStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transfers"
        window.contentView = NSHostingView(rootView: TransferProgressWindow(store: store))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        Self.window = window
    }
}
