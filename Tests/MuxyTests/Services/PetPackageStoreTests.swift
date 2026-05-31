import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Muxy

@Suite("PetPackageStore")
@MainActor
struct PetPackageStoreTests {
    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pet-store-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeAtlas(width: Int, height: Int, to url: URL) {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            )
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    @discardableResult
    private func makePackage(
        in root: URL, id: String, spritesheetPath: String = "spritesheet.png",
        atlasWidth: Int = PetAtlas.width, atlasHeight: Int = PetAtlas.height, writeManifest: Bool = true
    ) -> URL {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writeAtlas(width: atlasWidth, height: atlasHeight, to: directory.appendingPathComponent("spritesheet.png"))
        if writeManifest {
            let manifest = """
            {"id":"\(id)","displayName":"\(id)","description":"d","spritesheetPath":"\(spritesheetPath)"}
            """
            try? manifest.data(using: .utf8)?.write(to: directory.appendingPathComponent("pet.json"))
        }
        return directory
    }

    private func makeStore(root: URL) -> PetPackageStore {
        PetPackageStore(
            scanRoots: [(root, .muxyCustom)],
            defaults: UserDefaults(suiteName: "pet-test-\(UUID().uuidString)")!
        )
    }

    @Test("Valid package loads from a temporary root")
    func validPackageLoads() {
        let root = makeRoot()
        makePackage(in: root, id: "banana-cat")
        let store = makeStore(root: root)
        #expect(store.packages.contains { $0.id == "banana-cat" })
    }

    @Test("Missing pet.json is ignored")
    func missingManifestIgnored() {
        let root = makeRoot()
        makePackage(in: root, id: "no-manifest", writeManifest: false)
        let store = makeStore(root: root)
        #expect(store.packages.isEmpty)
    }

    @Test("spritesheetPath escaping the package directory is rejected")
    func escapingSpritesheetRejected() {
        let root = makeRoot()
        makePackage(in: root, id: "escaper", spritesheetPath: "../escaper/spritesheet.png")
        writeAtlas(width: PetAtlas.width, height: PetAtlas.height, to: root.appendingPathComponent("outside.png"))
        let directory = root.appendingPathComponent("escaper", isDirectory: true)
        let manifest = """
        {"id":"escaper","displayName":"e","description":"d","spritesheetPath":"../outside.png"}
        """
        try? manifest.data(using: .utf8)?.write(to: directory.appendingPathComponent("pet.json"))
        let store = makeStore(root: root)
        #expect(!store.packages.contains { $0.id == "escaper" })
    }

    @Test("Missing spritesheet is ignored")
    func missingSpritesheetIgnored() {
        let root = makeRoot()
        let directory = root.appendingPathComponent("no-atlas", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = """
        {"id":"no-atlas","displayName":"n","description":"d","spritesheetPath":"spritesheet.png"}
        """
        try? manifest.data(using: .utf8)?.write(to: directory.appendingPathComponent("pet.json"))
        let store = makeStore(root: root)
        #expect(!store.packages.contains { $0.id == "no-atlas" })
    }

    @Test("Wrong atlas dimensions are rejected")
    func wrongDimensionsRejected() {
        let root = makeRoot()
        makePackage(in: root, id: "tiny", atlasWidth: 10, atlasHeight: 10)
        let store = makeStore(root: root)
        #expect(!store.packages.contains { $0.id == "tiny" })
    }

    @Test("Selected pet falls back when the saved id no longer exists")
    func selectedFallback() {
        let root = makeRoot()
        makePackage(in: root, id: "alpha")
        makePackage(in: root, id: "beta")
        let defaults = UserDefaults(suiteName: "pet-test-\(UUID().uuidString)")!
        defaults.set("nonexistent", forKey: PetSettings.Key.selectedID)
        let store = PetPackageStore(scanRoots: [(root, .muxyCustom)], defaults: defaults)
        #expect(store.selectedPackage != nil)
        #expect(store.packages.contains { $0.id == store.selectedPackage?.id })
    }
}
