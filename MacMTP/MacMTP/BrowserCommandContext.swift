import SwiftUI

struct BrowserCommandContext {
    let title: String
    let canGoBack: Bool
    let canGoForward: Bool
    let canGoUp: Bool
    let canRefresh: Bool
    let canCreateTab: Bool
    let canCloseTab: Bool
    let tabCount: Int

    let goBack: () -> Void
    let goForward: () -> Void
    let goUp: () -> Void
    let refresh: () -> Void
    let newTab: () -> Void
    let closeTab: () -> Void
    let selectPreviousTab: () -> Void
    let selectNextTab: () -> Void
    let selectTab: (Int) -> Void
}

private struct BrowserCommandContextKey: FocusedValueKey {
    typealias Value = BrowserCommandContext
}

extension FocusedValues {
    var browserCommandContext: BrowserCommandContext? {
        get { self[BrowserCommandContextKey.self] }
        set { self[BrowserCommandContextKey.self] = newValue }
    }
}

