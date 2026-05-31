import Foundation
import Testing

@testable import Muxy

@Suite("PetStateController")
@MainActor
struct PetStateControllerTests {
    private func makeNotification() -> MuxyNotification {
        MuxyNotification(
            paneID: UUID(), projectID: UUID(), worktreeID: UUID(), areaID: UUID(),
            tabID: UUID(), worktreePath: "/tmp", source: .osc, title: "t", body: "b"
        )
    }

    @Test("Pulse overrides the ambient state")
    func pulseOverridesAmbient() {
        let controller = PetStateController()
        controller.trigger(.failed)
        #expect(controller.resolvedState(ambient: .idle) == .failed)
    }

    @Test("resolvedState returns ambient when no pulse is active")
    func ambientWhenIdle() {
        let controller = PetStateController()
        #expect(controller.resolvedState(ambient: .running) == .running)
    }

    @Test("react(to:) pulses waving")
    func reactPulsesWaving() {
        let controller = PetStateController()
        controller.react(to: makeNotification())
        #expect(controller.resolvedState(ambient: .idle) == .waving)
    }

    @Test("Repeated same-state trigger is ignored")
    func repeatedTriggerIgnored() {
        let controller = PetStateController()
        controller.trigger(.waving)
        controller.trigger(.waving)
        #expect(controller.resolvedState(ambient: .idle) == .waving)
    }

    @Test("Pulse falls back to ambient after the holding window")
    func pulseFallsBack() async {
        let controller = PetStateController()
        controller.trigger(.waving, holding: .milliseconds(20))
        #expect(controller.pulse == .waving)
        for _ in 0 ..< 100 where controller.pulse != nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.pulse == nil)
        #expect(controller.resolvedState(ambient: .running) == .running)
    }
}
