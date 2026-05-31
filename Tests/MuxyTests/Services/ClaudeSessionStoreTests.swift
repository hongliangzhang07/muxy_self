import Foundation
import Testing

@testable import Muxy

@Suite("ClaudeSessionStore")
@MainActor
struct ClaudeSessionStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-claude-store-\(UUID().uuidString).json")
    }

    @Test("autoConfirm is false by default and round-trips per project")
    func autoConfirmRoundTrip() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ClaudeSessionStore(fileURL: url)
        #expect(store.autoConfirm(forProject: "/tmp/p") == false)

        store.setAutoConfirm(true, forProject: "/tmp/p")
        #expect(store.autoConfirm(forProject: "/tmp/p"))

        let reloaded = ClaudeSessionStore(fileURL: url)
        #expect(reloaded.autoConfirm(forProject: "/tmp/p"))
        #expect(reloaded.autoConfirm(forProject: "/tmp/other") == false)
    }

    @Test("Legacy store file without autoConfirmByProject decodes without data loss")
    func decodesLegacyFile() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ClaudeSessionStore(fileURL: url)
        store.addSession(forProject: "/tmp/p", name: "S")

        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json.removeValue(forKey: "autoConfirmByProject")
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let reloaded = ClaudeSessionStore(fileURL: url)
        #expect(reloaded.sessions(forProject: "/tmp/p").count == 1)
        #expect(reloaded.autoConfirm(forProject: "/tmp/p") == false)
    }
}
