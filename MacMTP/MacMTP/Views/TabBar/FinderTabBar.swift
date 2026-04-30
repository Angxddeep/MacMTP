import SwiftUI

struct FinderTabBar: View {
    let tabs: [BrowserTab]
    @Binding var selectedTabID: BrowserTab.ID?
    let onCloseTab: () -> Void
    let canCloseTab: Bool
    @Namespace private var selectedTabNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                FinderTabButton(
                    tab: tab,
                    shortcutNumber: index + 1,
                    namespace: selectedTabNamespace,
                    isSelected: selectedTabID == tab.id,
                    canClose: canCloseTab,
                    onSelect: {
                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.12)) {
                            selectedTabID = tab.id
                        }
                    },
                    onClose: {
                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.12)) {
                            onCloseTab()
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                    removal: .opacity.combined(with: .scale(scale: 0.96))
                ))
            }
        }
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.12), value: tabs.map(\.id))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct FinderTabButton: View {
    @ObservedObject var tab: BrowserTab
    let shortcutNumber: Int
    let namespace: Namespace.ID
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                if isSelected && canClose && isHovering {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onClose)
                }

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                if let shortcutHint {
                    Text(shortcutHint)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 12)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(.tertiary)
                        .matchedGeometryEffect(id: "selectedTabPill", in: namespace)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(.white.opacity(0.26), lineWidth: 1)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tab.title)
    }

    private var shortcutHint: String? {
        switch shortcutNumber {
        case 1...9:
            return "⌘\(shortcutNumber)"
        case 10:
            return "⌘0"
        default:
            return nil
        }
    }
}
