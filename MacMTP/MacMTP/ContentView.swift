import SwiftUI

struct ContentView: View {
    @StateObject private var localViewModel = LocalBrowserViewModel()
    @StateObject private var mtpViewModel = MTPBrowserViewModel()
    
    var body: some View {
        HSplitView {
            FileBrowserPaneView(
                title: "This Mac",
                currentPath: localViewModel.currentPath,
                files: localViewModel.files,
                isLoading: localViewModel.isLoading,
                errorMessage: localViewModel.errorMessage,
                onNavigateTo: { path in localViewModel.navigateTo(path: path) },
                onNavigateBack: { localViewModel.navigateBack() },
                onNavigateForward: { localViewModel.navigateForward() },
                canGoBack: localViewModel.canGoBack,
                canGoForward: localViewModel.canGoForward
            )
            .frame(minWidth: 300)
            
            FileBrowserPaneView(
                title: "Phone (MTP)",
                currentPath: mtpViewModel.currentPath,
                files: mtpViewModel.files,
                isLoading: mtpViewModel.isLoading,
                errorMessage: mtpViewModel.errorMessage,
                onNavigateTo: { path in mtpViewModel.navigateTo(path: path) },
                onNavigateBack: { mtpViewModel.navigateBack() },
                onNavigateForward: { mtpViewModel.navigateForward() },
                canGoBack: mtpViewModel.canGoBack,
                canGoForward: mtpViewModel.canGoForward
            )
            .frame(minWidth: 300)
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    localViewModel.loadFiles()
                    mtpViewModel.loadFiles()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
