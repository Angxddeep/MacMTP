import SwiftUI

struct BrowserCommands: Commands {
    @FocusedValue(\.browserCommandContext) private var commandContext

    var body: some Commands {
        SidebarCommands()
        ToolbarCommands()

        CommandMenu("Browser") {
            Button("Back") {
                commandContext?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(commandContext?.canGoBack != true)

            Button("Forward") {
                commandContext?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(commandContext?.canGoForward != true)

            Button("Enclosing Folder") {
                commandContext?.goUp()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(commandContext?.canGoUp != true)

            Divider()

            Button("Refresh") {
                commandContext?.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(commandContext?.canRefresh != true)
        }

        CommandMenu("Tabs") {
            Button("New Tab") {
                commandContext?.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(commandContext?.canCreateTab != true)

            Button("Close Tab") {
                commandContext?.closeTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(commandContext?.canCloseTab != true)

            Divider()

            Button("Previous Tab") {
                commandContext?.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled((commandContext?.tabCount ?? 0) < 2)

            Button("Next Tab") {
                commandContext?.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled((commandContext?.tabCount ?? 0) < 2)

            Divider()

            ForEach(0..<min(commandContext?.tabCount ?? 0, 10), id: \.self) { index in
                Button("Select Tab \(index + 1)") {
                    commandContext?.selectTab(index)
                }
                .keyboardShortcut(tabShortcut(for: index), modifiers: .command)
            }
        }
    }

    private func tabShortcut(for index: Int) -> KeyEquivalent {
        index == 9 ? "0" : KeyEquivalent(Character("\(index + 1)"))
    }
}

