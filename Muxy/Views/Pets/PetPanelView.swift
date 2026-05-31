import SwiftUI

struct PetPanelView: View {
    let appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var packageStore = PetPackageStore.shared
    @State private var stateController = PetStateController.shared
    @State private var progressStore = TerminalProgressStore.shared

    @AppStorage(PetSettings.Key.size) private var size = PetSettings.Default.size

    private var petHeight: CGFloat {
        size * CGFloat(PetAtlas.cellHeight) / CGFloat(PetAtlas.cellWidth)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: UIMetrics.spacing2) {
            if let message = stateController.message {
                PetBubble(message: message) {
                    NotificationStore.shared.navigate(toNotification: message.notificationID)
                    stateController.dismissMessage()
                }
            }
            if let package = packageStore.selectedPackage {
                PetAnimationView(
                    package: package,
                    state: stateController.resolvedState(ambient: ambientState),
                    reduceMotion: reduceMotion
                )
                .frame(width: size, height: petHeight)
            }
        }
        .fixedSize()
        .onChange(of: stateController.message) { PetWindowController.shared.fitToContent() }
        .onChange(of: size) { PetWindowController.shared.fitToContent() }
        .accessibilityHidden(true)
    }

    private var ambientState: PetState {
        let activeTab = appState.activeProjectID.flatMap { appState.activeTab(for: $0) }
        let activePane = activeTab?.content.pane
        return PetSignal.state(for: PetSignal.Input(
            hasActiveProject: appState.activeProjectID != nil,
            activeTabKind: activeTab?.kind,
            activeProgress: activePane.flatMap { progressStore.progress(for: $0.id) },
            completionPending: activePane.map { progressStore.isCompletionPending(for: $0.id) } ?? false,
            hasActiveTerminalPane: activePane != nil
        ))
    }
}

private struct PetBubble: View {
    let message: PetStateController.Message
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message.title)
                .font(.system(size: UIMetrics.fontFootnote, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
                .lineLimit(1)
            if !message.body.isEmpty {
                Text(message.body)
                    .font(.system(size: UIMetrics.fontFootnote))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, UIMetrics.spacing3)
        .padding(.vertical, UIMetrics.spacing2)
        .frame(maxWidth: 220, alignment: .leading)
        .background(MuxyTheme.bg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MuxyTheme.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onTap)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}
