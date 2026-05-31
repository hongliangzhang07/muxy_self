import Foundation

/// Muxy fork (CCH parity): a persistent, named Claude Code conversation bound to a
/// project. Mirrors a CCH "thread": each session owns a stable `claudeSessionId`
/// that is generated once at creation and reused forever, so reopening the project
/// resumes THE SAME conversation (`claude --resume <id>`) instead of starting fresh.
struct ClaudeSession: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// The UUID passed to `claude --session-id` (create) / `claude --resume` (reopen).
    let claudeSessionId: String
    let projectPath: String
    var createdAt: Date
    var lastActiveAt: Date
    var order: Int
    /// Whether this session's Claude conversation has been created yet (via
    /// `--session-id`). Mirrors CCH's `isResume`: first launch CREATES, later
    /// launches RESUME. Avoids running `--resume` on a not-yet-created session
    /// (which prints "No conversation found" and does not fall through reliably
    /// in an interactive terminal).
    var hasLaunched: Bool

    init(
        id: UUID = UUID(),
        name: String,
        claudeSessionId: String = UUID().uuidString.lowercased(),
        projectPath: String,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        order: Int = 0,
        hasLaunched: Bool = false
    ) {
        self.id = id
        self.name = name
        self.claudeSessionId = claudeSessionId
        self.projectPath = projectPath
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.order = order
        self.hasLaunched = hasLaunched
    }

    // Decode with default so older store files (without hasLaunched) still load.
    enum CodingKeys: String, CodingKey {
        case id, name, claudeSessionId, projectPath, createdAt, lastActiveAt, order, hasLaunched
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        claudeSessionId = try c.decode(String.self, forKey: .claudeSessionId)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastActiveAt = try c.decode(Date.self, forKey: .lastActiveAt)
        order = try c.decode(Int.self, forKey: .order)
        hasLaunched = try c.decodeIfPresent(Bool.self, forKey: .hasLaunched) ?? false
    }

    /// Shell command muxy runs in the pane (executed lazily — only when this
    /// session's tab is first rendered/clicked, NOT at app launch).
    ///
    /// Self-healing & idempotent, so it works regardless of whether the
    /// conversation already exists, and needs no "has it launched yet?" bookkeeping:
    ///   - conversation exists  → `claude --resume <id>` reattaches
    ///   - conversation missing → `--resume` exits non-zero → `|| claude --session-id <id>`
    ///                            CREATES it with the SAME stable id
    /// The id is a stored constant, so the fallback never spawns a new random
    /// session — it always reuses this session's id. Drops to a login shell on exit.
    func launchCommand(autoConfirm: Bool) -> String {
        let flag = autoConfirm ? "--dangerously-skip-permissions " : ""
        let claude = "claude \(flag)--resume \(claudeSessionId) || claude \(flag)--session-id \(claudeSessionId)"
        return "(\(claude)); exec \"$0\" -l"
    }
}
