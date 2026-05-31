import Foundation
import Testing

@testable import Muxy

@Suite("PetAnimation")
struct PetAnimationTests {
    @Test("Atlas dimensions match the package contract")
    func atlasDimensions() {
        #expect(PetAtlas.width == 1536)
        #expect(PetAtlas.height == 1872)
        #expect(PetAtlas.columns == 8)
        #expect(PetAtlas.rows == 9)
        #expect(PetAtlas.cellWidth == 192)
        #expect(PetAtlas.cellHeight == 208)
    }

    @Test("Each state maps to the expected row, frame count, and durations")
    func stateSpecs() {
        #expect(PetState.idle.rowIndex == 0)
        #expect(PetState.idle.durationsMs == [280, 110, 110, 140, 140, 320])
        #expect(PetState.runningRight.rowIndex == 1)
        #expect(PetState.runningRight.frameCount == 8)
        #expect(PetState.waving.rowIndex == 3)
        #expect(PetState.waving.durationsMs == [140, 140, 140, 280])
        #expect(PetState.failed.rowIndex == 5)
        #expect(PetState.failed.frameCount == 8)
        #expect(PetState.waiting.rowIndex == 6)
        #expect(PetState.running.rowIndex == 7)
        #expect(PetState.review.rowIndex == 8)
        #expect(PetState.review.durationsMs == [150, 150, 150, 150, 150, 280])

        for state in PetState.allCases {
            #expect(state.frameCount == state.durationsMs.count)
            #expect(state.rowIndex < PetAtlas.rows)
            #expect(state.frameCount <= PetAtlas.columns)
        }
    }

    @Test("Frame rectangle geometry is correct")
    func frameRect() {
        let idleFrame2 = PetState.idle.frameRect(at: 2)
        #expect(idleFrame2 == CGRect(x: 384, y: 0, width: 192, height: 208))

        let runningFrame1 = PetState.running.frameRect(at: 1)
        #expect(runningFrame1 == CGRect(x: 192, y: 1456, width: 192, height: 208))
    }

    @Test("Frame index is clamped to the valid range")
    func frameRectClamped() {
        let upper = PetState.waving.frameRect(at: 99)
        #expect(upper == CGRect(
            x: (PetState.waving.frameCount - 1) * PetAtlas.cellWidth,
            y: PetState.waving.rowIndex * PetAtlas.cellHeight,
            width: PetAtlas.cellWidth,
            height: PetAtlas.cellHeight
        ))

        let lower = PetState.running.frameRect(at: -1)
        #expect(lower == CGRect(
            x: 0,
            y: PetState.running.rowIndex * PetAtlas.cellHeight,
            width: PetAtlas.cellWidth,
            height: PetAtlas.cellHeight
        ))
    }

    @Test("Normalized frame rectangle uses unit coordinates")
    func normalizedFrameRect() {
        let rect = PetState.idle.normalizedFrameRect(at: 0)
        #expect(rect.origin == .zero)
        #expect(abs(rect.width - CGFloat(192) / 1536) < 0.0001)
        #expect(abs(rect.height - CGFloat(208) / 1872) < 0.0001)
    }

    @Test("PetSignal maps idle when there is no active project")
    func signalNoProject() {
        let state = PetSignal.state(for: .init(
            hasActiveProject: false, activeTabKind: nil, activeProgress: nil,
            completionPending: false, hasActiveTerminalPane: false
        ))
        #expect(state == .idle)
    }

    @Test("PetSignal maps progress kinds to running/waiting/failed")
    func signalProgress() {
        func state(_ kind: TerminalProgress.Kind) -> PetState {
            PetSignal.state(for: .init(
                hasActiveProject: true, activeTabKind: .terminal,
                activeProgress: TerminalProgress(kind: kind, percent: nil),
                completionPending: false, hasActiveTerminalPane: true
            ))
        }
        #expect(state(.set) == .running)
        #expect(state(.indeterminate) == .running)
        #expect(state(.paused) == .waiting)
        #expect(state(.error) == .failed)
    }

    @Test("PetSignal maps source control and diff tabs to review")
    func signalReview() {
        for kind in [TerminalTab.Kind.vcs, .diffViewer] {
            let state = PetSignal.state(for: .init(
                hasActiveProject: true, activeTabKind: kind, activeProgress: nil,
                completionPending: false, hasActiveTerminalPane: false
            ))
            #expect(state == .review)
        }
    }

    @Test("PetSignal maps completion pending to waving and idle terminal to idle")
    func signalCompletionAndDefault() {
        let waving = PetSignal.state(for: .init(
            hasActiveProject: true, activeTabKind: .terminal, activeProgress: nil,
            completionPending: true, hasActiveTerminalPane: true
        ))
        #expect(waving == .waving)

        let idle = PetSignal.state(for: .init(
            hasActiveProject: true, activeTabKind: .terminal, activeProgress: nil,
            completionPending: false, hasActiveTerminalPane: true
        ))
        #expect(idle == .idle)

        let waiting = PetSignal.state(for: .init(
            hasActiveProject: true, activeTabKind: .editor, activeProgress: nil,
            completionPending: false, hasActiveTerminalPane: false
        ))
        #expect(waiting == .waiting)
    }
}
