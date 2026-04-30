import SwiftUI
import Combine

final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    let localViewModel: LocalBrowserViewModel
    let mtpViewModel: MTPBrowserViewModel

    @Published var selectedDestination: SidebarDestination
    private var cancellables = Set<AnyCancellable>()

    init(startingFavorite: FavoriteLocation) {
        selectedDestination = .favorite(startingFavorite.path)
        localViewModel = LocalBrowserViewModel(startingPath: startingFavorite.path)
        mtpViewModel = MTPBrowserViewModel()

        localViewModel.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        mtpViewModel.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    var title: String {
        switch selectedDestination {
        case .favorite:
            return localViewModel.currentPath.replacingOccurrences(
                of: NSHomeDirectory(),
                with: "~",
                options: [.anchored]
            )
        case .phone:
            return "Phone"
        }
    }
}

@MainActor
final class BrowserTabStore: ObservableObject {
    @Published var tabs: [BrowserTab]
    @Published var selectedTabID: BrowserTab.ID?

    private let startingFavorite: FavoriteLocation

    init(startingFavorite: FavoriteLocation) {
        self.startingFavorite = startingFavorite
        let firstTab = BrowserTab(startingFavorite: startingFavorite)
        tabs = [firstTab]
        selectedTabID = firstTab.id
    }

    var selectedTab: BrowserTab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    var canCreateTab: Bool {
        true
    }

    func createTab() {
        let tab = BrowserTab(startingFavorite: startingFavorite)
        if let selectedTab,
           let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTab.id }) {
            tabs.insert(tab, at: selectedIndex + 1)
        } else {
            tabs.append(tab)
        }
        selectedTabID = tab.id
    }

    func closeSelectedTab() {
        guard tabs.count > 1, let selectedTab else { return }
        let oldIndex = tabs.firstIndex { $0.id == selectedTab.id } ?? 0
        tabs.removeAll { $0.id == selectedTab.id }
        selectedTabID = tabs[min(oldIndex, tabs.count - 1)].id
    }

    func selectTab(at index: Int) {
        guard !tabs.isEmpty else { return }
        selectedTabID = tabs[min(max(index, 0), tabs.count - 1)].id
    }

    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        let selectedIndex = selectedTab.flatMap { selectedTab in
            tabs.firstIndex { $0.id == selectedTab.id }
        } ?? 0
        let nextIndex = selectedIndex == 0 ? tabs.count - 1 : selectedIndex - 1
        selectedTabID = tabs[nextIndex].id
    }

    func selectNextTab() {
        guard tabs.count > 1 else { return }
        let selectedIndex = selectedTab.flatMap { selectedTab in
            tabs.firstIndex { $0.id == selectedTab.id }
        } ?? 0
        let nextIndex = selectedIndex == tabs.count - 1 ? 0 : selectedIndex + 1
        selectedTabID = tabs[nextIndex].id
    }
}
