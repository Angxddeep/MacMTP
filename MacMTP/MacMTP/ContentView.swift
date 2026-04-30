import SwiftUI
import AppKit

struct ContentView: View {
    @AppStorage("favoriteLocations") private var favoriteLocationsData: Data = Data()
    @StateObject private var tabStore: BrowserTabStore
    @State private var favorites: [FavoriteLocation]

    init() {
        let defaultFavorites = FavoriteLocation.defaultFavorites
        let startingFavorite = defaultFavorites.first ?? FavoriteLocation(name: "Home", path: NSHomeDirectory())
        _favorites = State(initialValue: defaultFavorites)
        _tabStore = StateObject(wrappedValue: BrowserTabStore(startingFavorite: startingFavorite))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                favorites: favorites,
                selectedDestination: selectedDestinationBinding,
                onAddFavorite: addFavorite,
                onDropLocalFilesToFavorite: dropLocalFilesToFavorite,
                onDropDraggedFilesToFavorite: dropDraggedFilesToFavorite,
                onDropLocalFilesToPhone: dropLocalFilesToPhone,
                onDropDraggedFilesToPhone: dropDraggedFilesToPhone
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                FinderTabBar(
                    tabs: tabStore.tabs,
                    selectedTabID: $tabStore.selectedTabID,
                    onCloseTab: tabStore.closeSelectedTab,
                    canCloseTab: tabStore.tabs.count > 1
                )

                if let selectedTab = tabStore.selectedTab {
                    BrowserDetailView(tab: selectedTab, favorites: favorites)
                } else {
                    ContentUnavailableView("No Tab", systemImage: "rectangle.on.rectangle.slash")
                }
            }
        }
        .frame(minWidth: 1260, minHeight: 660)
        .navigationTitle(browserCommandContext.title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: browserCommandContext.goBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(!browserCommandContext.canGoBack)
                .help("Back")

                Button(action: browserCommandContext.goForward) {
                    Label("Forward", systemImage: "chevron.right")
                }
                .disabled(!browserCommandContext.canGoForward)
                .help("Forward")

                Button(action: browserCommandContext.goUp) {
                    Label("Enclosing Folder", systemImage: "arrow.up")
                }
                .disabled(!browserCommandContext.canGoUp)
                .help("Enclosing Folder")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: browserCommandContext.refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!browserCommandContext.canRefresh)
                .help("Refresh")

                Button(action: browserCommandContext.newTab) {
                    Label("New Tab", systemImage: "plus")
                }
                .disabled(!browserCommandContext.canCreateTab)
                .help("New Tab")
            }
        }
        .focusedValue(\.browserCommandContext, browserCommandContext)
        .background(BrowserKeyboardShortcutHandler(commandContext: browserCommandContext))
        .onAppear(perform: loadFavorites)
    }

    private var browserCommandContext: BrowserCommandContext {
        guard let selectedTab = tabStore.selectedTab else {
            return makeBrowserCommandContext(
                title: "No Tab",
                canGoBack: false,
                canGoForward: false,
                canGoUp: false,
                canRefresh: false,
                goBack: {},
                goForward: {},
                goUp: {},
                refresh: {}
            )
        }

        switch selectedTab.selectedDestination {
        case let .favorite(path):
            let viewModel = selectedTab.localViewModel
            return makeBrowserCommandContext(
                title: title(forFavoriteAt: path),
                canGoBack: viewModel.canGoBack,
                canGoForward: viewModel.canGoForward,
                canGoUp: viewModel.currentPath != "/",
                canRefresh: !viewModel.isLoading,
                goBack: { viewModel.navigateBack() },
                goForward: { viewModel.navigateForward() },
                goUp: { viewModel.navigateUp() },
                refresh: { viewModel.loadFiles() }
            )
        case .phone:
            let viewModel = selectedTab.mtpViewModel
            return makeBrowserCommandContext(
                title: "Phone",
                canGoBack: viewModel.canGoBack,
                canGoForward: viewModel.canGoForward,
                canGoUp: viewModel.currentPath != "/Internal Storage" && viewModel.currentPath != "/",
                canRefresh: !viewModel.isLoading,
                goBack: { viewModel.navigateBack() },
                goForward: { viewModel.navigateForward() },
                goUp: { viewModel.navigateUp() },
                refresh: { viewModel.loadFiles() }
            )
        }
    }

    private func makeBrowserCommandContext(
        title: String,
        canGoBack: Bool,
        canGoForward: Bool,
        canGoUp: Bool,
        canRefresh: Bool,
        goBack: @escaping () -> Void,
        goForward: @escaping () -> Void,
        goUp: @escaping () -> Void,
        refresh: @escaping () -> Void
    ) -> BrowserCommandContext {
        BrowserCommandContext(
            title: title,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            canGoUp: canGoUp,
            canRefresh: canRefresh,
            canCreateTab: tabStore.canCreateTab,
            canCloseTab: tabStore.tabs.count > 1,
            tabCount: tabStore.tabs.count,
            goBack: goBack,
            goForward: goForward,
            goUp: goUp,
            refresh: refresh,
            newTab: { tabStore.createTab() },
            closeTab: { tabStore.closeSelectedTab() },
            selectPreviousTab: { tabStore.selectPreviousTab() },
            selectNextTab: { tabStore.selectNextTab() },
            selectTab: { tabStore.selectTab(at: $0) }
        )
    }

    private var selectedDestinationBinding: Binding<SidebarDestination?> {
        Binding {
            tabStore.selectedTab?.selectedDestination
        } set: { newValue in
            guard let selectedTab = tabStore.selectedTab, let newValue else { return }

            DispatchQueue.main.async {
                selectedTab.selectedDestination = newValue

                if case let .favorite(path) = newValue {
                    selectedTab.localViewModel.navigateTo(path: path)
                }
            }
        }
    }

    private func title(forFavoriteAt path: String) -> String {
        favorites.first { $0.path == path }?.name ?? FileManager.default.displayName(atPath: path)
    }

    private func loadFavorites() {
        guard !favoriteLocationsData.isEmpty,
              let decoded = try? JSONDecoder().decode([FavoriteLocation].self, from: favoriteLocationsData)
        else {
            persistFavorites()
            return
        }

        let existingFavorites = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
        favorites = existingFavorites.isEmpty ? FavoriteLocation.defaultFavorites : existingFavorites
    }

    private func persistFavorites() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            favoriteLocationsData = encoded
        }
    }

    private func addFavorite() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let favorite = FavoriteLocation(
            name: FileManager.default.displayName(atPath: url.path),
            path: url.path
        )

        guard !favorites.contains(where: { $0.path == favorite.path }) else { return }
        favorites.append(favorite)
        persistFavorites()
    }

    private func dropLocalFilesToFavorite(_ urls: [URL], favorite: FavoriteLocation) async {
        guard let selectedTab = tabStore.selectedTab else { return }
        await selectedTab.localViewModel.copyLocalFiles(urls, toDirectory: favorite.path)
    }

    private func dropDraggedFilesToFavorite(_ items: [FileDragItem], favorite: FavoriteLocation) async {
        guard let selectedTab = tabStore.selectedTab else { return }
        await selectedTab.localViewModel.importDraggedItems(
            items,
            toDirectory: favorite.path,
            mtpViewModel: selectedTab.mtpViewModel
        )
    }

    private func dropLocalFilesToPhone(_ urls: [URL]) async {
        guard let selectedTab = tabStore.selectedTab else { return }
        await selectedTab.mtpViewModel.uploadLocalFiles(urls, toDirectory: "/Internal Storage")
    }

    private func dropDraggedFilesToPhone(_ items: [FileDragItem]) async {
        guard let selectedTab = tabStore.selectedTab else { return }
        await selectedTab.mtpViewModel.importDraggedItems(items, toDirectory: "/Internal Storage")
    }
}

#Preview {
    ContentView()
}

private struct BrowserKeyboardShortcutHandler: View {
    let commandContext: BrowserCommandContext

    var body: some View {
        VStack(spacing: 0) {
            Button("") {
                commandContext.closeTab()
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("") {
                commandContext.closeTab()
            }
            .keyboardShortcut("w", modifiers: .control)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
