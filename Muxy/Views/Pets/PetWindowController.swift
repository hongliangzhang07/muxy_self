import AppKit
import SwiftUI

@MainActor
final class PetWindowController {
    static let shared = PetWindowController()

    private var panel: NSPanel?
    private weak var appState: AppState?
    private var defaultsObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var lastOriginX: CGFloat?
    private var isShown = false
    private var lastAppliedSize: CGFloat?
    private var screenObserver: NSObjectProtocol?

    private static let frameAutosaveName = "muxy.pet.window"

    func start(appState: AppState) {
        self.appState = appState
        applyState()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyState() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.ensureOnScreen() }
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: PetSettings.Key.enabled) as? Bool ?? PetSettings.Default.enabled
    }

    private var petSize: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: PetSettings.Key.size) as? Double ?? PetSettings.Default.size)
    }

    private func applyState() {
        guard isEnabled, let appState else {
            if isShown {
                panel?.orderOut(nil)
                isShown = false
            }
            return
        }
        let panel = ensurePanel(appState: appState)
        if lastAppliedSize != petSize {
            lastAppliedSize = petSize
            fitToContent()
        }
        if !isShown {
            panel.orderFrontRegardless()
            isShown = true
        }
    }

    private func ensurePanel(appState: AppState) -> NSPanel {
        if let panel { return panel }

        let height = petSize * CGFloat(PetAtlas.cellHeight) / CGFloat(PetAtlas.cellWidth)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: petSize, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: PetPanelView(appState: appState))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        _ = panel.setFrameAutosaveName(Self.frameAutosaveName)
        if !isFrameOnVisibleScreen(panel.frame) {
            positionDefault(panel)
        }

        self.panel = panel
        observeMoves(panel)
        return panel
    }

    private func isFrameOnVisibleScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width >= 20 && overlap.height >= 20
        }
    }

    private func ensureOnScreen() {
        guard let panel, !isFrameOnVisibleScreen(panel.frame) else { return }
        positionDefault(panel)
    }

    func fitToContent() {
        guard let panel, let hosting = panel.contentView else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let width = max(fitting.width, 1)
        let height = max(fitting.height, 1)
        let old = panel.frame
        guard old.width != width || old.height != height else { return }
        panel.setFrame(
            NSRect(x: old.maxX - width, y: old.minY, width: width, height: height),
            display: true
        )
        lastOriginX = panel.frame.origin.x
    }

    private func positionDefault(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - panel.frame.width - 24,
            y: visible.minY + 24
        ))
    }

    private func observeMoves(_ panel: NSPanel) {
        lastOriginX = panel.frame.origin.x
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMove() }
        }
    }

    private func handleMove() {
        guard let panel else { return }
        let newX = panel.frame.origin.x
        defer { lastOriginX = newX }
        guard let last = lastOriginX, abs(newX - last) > 1 else { return }
        PetStateController.shared.reportMovement(towardRight: newX - last >= 0)
    }
}
