import SwiftUI

struct BrowserDetailView: View {
    @ObservedObject var tab: BrowserTab
    let favorites: [FavoriteLocation]

    var body: some View {
        switch tab.selectedDestination {
        case let .favorite(path):
            LocalBrowserDetailView(
                title: title(forFavoriteAt: path),
                viewModel: tab.localViewModel,
                mtpViewModel: tab.mtpViewModel
            )
        case .phone:
            MTPBrowserDetailView(viewModel: tab.mtpViewModel)
        }
    }

    private func title(forFavoriteAt path: String) -> String {
        favorites.first { $0.path == path }?.name ?? FileManager.default.displayName(atPath: path)
    }
}

struct LocalBrowserDetailView: View {
    let title: String
    @ObservedObject var viewModel: LocalBrowserViewModel
    @ObservedObject var mtpViewModel: MTPBrowserViewModel

    var body: some View {
        FileBrowserPaneView(
            title: title,
            location: .local,
            currentPath: viewModel.currentPath,
            files: viewModel.files,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            onNavigateTo: { path in viewModel.navigateTo(path: path) },
            onDropLocalFiles: { urls, directoryPath in
                await viewModel.copyLocalFiles(urls, toDirectory: directoryPath)
            },
            onDropDraggedFiles: { items, directoryPath in
                await viewModel.importDraggedItems(
                    items,
                    toDirectory: directoryPath,
                    mtpViewModel: mtpViewModel
                )
            }
        )
        .navigationTitle(title)
    }
}

struct MTPBrowserDetailView: View {
    @ObservedObject var viewModel: MTPBrowserViewModel

    var body: some View {
        FileBrowserPaneView(
            title: viewModel.isConnected ? "Phone (MTP)" : "Phone (MTP) - Connecting...",
            location: .mtp,
            currentPath: viewModel.currentPath,
            files: viewModel.files,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            onNavigateTo: { path in viewModel.navigateTo(path: path) },
            onDropLocalFiles: { urls, directoryPath in
                await viewModel.uploadLocalFiles(urls, toDirectory: directoryPath)
            },
            onDropDraggedFiles: { items, directoryPath in
                await viewModel.importDraggedItems(items, toDirectory: directoryPath)
            }
        )
        .navigationTitle("Phone")
    }
}

