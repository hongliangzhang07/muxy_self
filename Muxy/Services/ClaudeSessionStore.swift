import Foundation

/// Muxy fork (CCH parity): persistent store of Claude sessions per project.
/// This is muxy's equivalent of CCH's `data.json` — it survives project close/reopen
/// AND app restart, so the project's session list (and each session's stable
/// `claudeSessionId`) is remembered and reused, not regenerated on every open.
///
/// File: ~/Library/Application Support/Muxy/claude-sessions.json
@MainActor
final class ClaudeSessionStore {
    static let shared = ClaudeSessionStore()

    private struct FileModel: Codable {
        var schemaVersion: Int
        var sessionsByProject: [String: [ClaudeSession]]
        var autoConfirmByProject: [String: Bool]

        init(
            schemaVersion: Int = 1,
            sessionsByProject: [String: [ClaudeSession]] = [:],
            autoConfirmByProject: [String: Bool] = [:]
        ) {
            self.schemaVersion = schemaVersion
            self.sessionsByProject = sessionsByProject
            self.autoConfirmByProject = autoConfirmByProject
        }

        enum CodingKeys: String, CodingKey {
            case schemaVersion, sessionsByProject, autoConfirmByProject
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            sessionsByProject = try container.decodeIfPresent([String: [ClaudeSession]].self, forKey: .sessionsByProject) ?? [:]
            autoConfirmByProject = try container.decodeIfPresent([String: Bool].self, forKey: .autoConfirmByProject) ?? [:]
        }
    }

    private let store: CodableFileStore<FileModel>
    private var model: FileModel

    init(fileURL: URL = MuxyFileStorage.fileURL(filename: "claude-sessions.json")) {
        store = CodableFileStore(fileURL: fileURL, options: .prettySorted)
        do {
            model = try store.load() ?? FileModel()
        } catch {
            // Corrupt/unreadable store: do NOT silently start empty and then
            // overwrite the (possibly recoverable) file. Preserve it as .corrupt
            // for manual recovery, log loudly, then continue with an empty model.
            NSLog("ClaudeSessionStore: load failed (\(error)); preserving file as .corrupt")
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            model = FileModel()
        }
    }

    // MARK: - Read

    /// Sessions for a project, ordered.
    func sessions(forProject path: String) -> [ClaudeSession] {
        (model.sessionsByProject[path] ?? []).sorted { $0.order < $1.order }
    }

    func session(id: UUID, forProject path: String) -> ClaudeSession? {
        model.sessionsByProject[path]?.first { $0.id == id }
    }

    func autoConfirm(forProject path: String) -> Bool {
        model.autoConfirmByProject[path] ?? false
    }

    func setAutoConfirm(_ enabled: Bool, forProject path: String) {
        model.autoConfirmByProject[path] = enabled
        persist()
    }

    /// Sessions for a project, creating one default session if none exist yet.
    /// Used when opening a project so there is always at least one session.
    func sessionsEnsuringDefault(forProject path: String) -> [ClaudeSession] {
        // Guard against an empty project path producing an orphan "" bucket.
        guard !path.isEmpty else {
            return [ClaudeSession(name: "Session 1", projectPath: path)]
        }
        let existing = sessions(forProject: path)
        if !existing.isEmpty { return existing }
        let session = ClaudeSession(name: "Session 1", projectPath: path, order: 0)
        model.sessionsByProject[path, default: []].append(session)
        persist()
        return [session]
    }

    // MARK: - Write

    @discardableResult
    func addSession(forProject path: String, name: String? = nil) -> ClaudeSession {
        let nextOrder = (model.sessionsByProject[path]?.map(\.order).max() ?? -1) + 1
        let sessionName = name ?? "Session \(nextOrder + 1)"
        let session = ClaudeSession(name: sessionName, projectPath: path, order: nextOrder)
        model.sessionsByProject[path, default: []].append(session)
        persist()
        return session
    }

    func rename(sessionID: UUID, forProject path: String, to name: String) {
        guard var arr = model.sessionsByProject[path],
              let idx = arr.firstIndex(where: { $0.id == sessionID }) else { return }
        arr[idx].name = name
        model.sessionsByProject[path] = arr
        persist()
    }

    func removeSession(sessionID: UUID, forProject path: String) {
        model.sessionsByProject[path]?.removeAll { $0.id == sessionID }
        if model.sessionsByProject[path]?.isEmpty == true {
            model.sessionsByProject.removeValue(forKey: path)
        }
        persist()
    }

    /// Mark a session as launched (its Claude conversation has been created),
    /// so future opens use `--resume` instead of `--session-id`. CCH-style.
    func markLaunched(sessionID: UUID, forProject path: String) {
        guard var arr = model.sessionsByProject[path],
              let idx = arr.firstIndex(where: { $0.id == sessionID }),
              !arr[idx].hasLaunched else { return }
        arr[idx].hasLaunched = true
        model.sessionsByProject[path] = arr
        persist()
    }

    func touch(sessionID: UUID, forProject path: String) {
        guard var arr = model.sessionsByProject[path],
              let idx = arr.firstIndex(where: { $0.id == sessionID }) else { return }
        arr[idx].lastActiveAt = Date()
        model.sessionsByProject[path] = arr
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try store.save(model)
        } catch {
            NSLog("ClaudeSessionStore: failed to persist: \(error)")
        }
    }
}
