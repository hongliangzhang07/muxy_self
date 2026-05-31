import CoreGraphics
import Foundation

enum PetAtlas {
    static let columns = 8
    static let rows = 9
    static let cellWidth = 192
    static let cellHeight = 208
    static let width = columns * cellWidth
    static let height = rows * cellHeight
}

enum PetState: String, CaseIterable {
    case idle
    case runningRight
    case runningLeft
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review

    var rowIndex: Int {
        switch self {
        case .idle: 0
        case .runningRight: 1
        case .runningLeft: 2
        case .waving: 3
        case .jumping: 4
        case .failed: 5
        case .waiting: 6
        case .running: 7
        case .review: 8
        }
    }

    var durationsMs: [Int] {
        switch self {
        case .idle: [280, 110, 110, 140, 140, 320]
        case .runningRight: [120, 120, 120, 120, 120, 120, 120, 220]
        case .runningLeft: [120, 120, 120, 120, 120, 120, 120, 220]
        case .waving: [140, 140, 140, 280]
        case .jumping: [140, 140, 140, 140, 280]
        case .failed: [140, 140, 140, 140, 140, 140, 140, 240]
        case .waiting: [150, 150, 150, 150, 150, 260]
        case .running: [120, 120, 120, 120, 120, 220]
        case .review: [150, 150, 150, 150, 150, 280]
        }
    }

    var frameCount: Int { durationsMs.count }

    var isTransient: Bool {
        switch self {
        case .waving,
             .jumping: true
        default: false
        }
    }

    func frameRect(at frameIndex: Int) -> CGRect {
        let column = max(0, min(frameIndex, frameCount - 1))
        return CGRect(
            x: column * PetAtlas.cellWidth,
            y: rowIndex * PetAtlas.cellHeight,
            width: PetAtlas.cellWidth,
            height: PetAtlas.cellHeight
        )
    }

    func normalizedFrameRect(at frameIndex: Int) -> CGRect {
        let rect = frameRect(at: frameIndex)
        return CGRect(
            x: rect.minX / CGFloat(PetAtlas.width),
            y: rect.minY / CGFloat(PetAtlas.height),
            width: rect.width / CGFloat(PetAtlas.width),
            height: rect.height / CGFloat(PetAtlas.height)
        )
    }
}

enum PetSignal {
    struct Input: Equatable {
        let hasActiveProject: Bool
        let activeTabKind: TerminalTab.Kind?
        let activeProgress: TerminalProgress?
        let completionPending: Bool
        let hasActiveTerminalPane: Bool
    }

    static func state(for input: Input) -> PetState {
        guard input.hasActiveProject else { return .idle }
        if let progress = input.activeProgress {
            switch progress.kind {
            case .error: return .failed
            case .paused: return .waiting
            case .set,
                 .indeterminate: return .running
            }
        }
        if input.activeTabKind == .vcs || input.activeTabKind == .diffViewer { return .review }
        if input.completionPending { return .waving }
        if !input.hasActiveTerminalPane { return .waiting }
        return .idle
    }
}
