import Foundation

@MainActor
@Observable
final class PetStateController {
    static let shared = PetStateController()

    struct Message: Equatable {
        let title: String
        let body: String
    }

    private(set) var pulse: PetState?
    private(set) var dragState: PetState?
    private(set) var message: Message?

    @ObservationIgnored private var clearTask: Task<Void, Never>?
    @ObservationIgnored private var dragClearTask: Task<Void, Never>?
    @ObservationIgnored private var messageClearTask: Task<Void, Never>?

    func react(to notification: MuxyNotification) {
        trigger(.waving)
        showMessage(Message(title: notification.title, body: notification.body))
    }

    func showMessage(_ newMessage: Message, holding duration: Duration = .seconds(5)) {
        message = newMessage
        messageClearTask?.cancel()
        messageClearTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.message = nil
            self?.messageClearTask = nil
        }
    }

    func reportMovement(towardRight: Bool) {
        dragState = towardRight ? .runningRight : .runningLeft
        dragClearTask?.cancel()
        dragClearTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.dragState = nil
            self?.dragClearTask = nil
        }
    }

    func trigger(_ state: PetState, holding duration: Duration = .milliseconds(1800)) {
        guard pulse != state else { return }
        pulse = state
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.pulse = nil
            self?.clearTask = nil
        }
    }

    func resolvedState(ambient: PetState) -> PetState {
        dragState ?? pulse ?? ambient
    }
}
