import Foundation
import ImageIO
import os

private let logger = Logger(subsystem: "app.muxy", category: "PetPackageStore")

@MainActor
@Observable
final class PetPackageStore {
    static let shared = PetPackageStore()

    private(set) var packages: [PetPackage] = []

    var selectedID: String {
        didSet { defaults.set(selectedID, forKey: PetSettings.Key.selectedID) }
    }

    @ObservationIgnored private let scanRoots: [(URL, PetPackage.Source)]
    @ObservationIgnored private let defaults: UserDefaults

    private static let maxManifestBytes = 64 * 1024
    private static let maxSpritesheetBytes = 64 * 1024 * 1024

    init(
        scanRoots: [(URL, PetPackage.Source)]? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.scanRoots = scanRoots ?? Self.defaultScanRoots()
        self.defaults = defaults
        selectedID = defaults.string(forKey: PetSettings.Key.selectedID) ?? PetSettings.Default.selectedID
        reload()
    }

    func reload() {
        var discovered: [PetPackage] = []
        var seenIDs = Set<String>()
        for (root, source) in scanRoots {
            for package in Self.scan(root: root, source: source) where !seenIDs.contains(package.id) {
                seenIDs.insert(package.id)
                discovered.append(package)
            }
        }
        packages = discovered
    }

    var selectedPackage: PetPackage? {
        packages.first { $0.id == selectedID } ?? packages.first
    }

    private static func defaultScanRoots() -> [(URL, PetPackage.Source)] {
        var roots: [(URL, PetPackage.Source)] = []
        if let bundled = Bundle.main.url(forResource: "Pets", withExtension: nil) {
            roots.append((bundled, .bundled))
        }
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        roots.append((codexHome.appendingPathComponent("pets"), .codexCustom))
        roots.append((MuxyFileStorage.appSupportDirectory().appendingPathComponent("Pets"), .muxyCustom))
        return roots
    }

    private static func scan(root: URL, source: PetPackage.Source) -> [PetPackage] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        else { return [] }

        return entries.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            return loadPackage(from: directory, source: source)
        }
    }

    private static func loadPackage(from directory: URL, source: PetPackage.Source) -> PetPackage? {
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard let manifest = decodeManifest(at: manifestURL) else { return nil }
        guard let spritesheetURL = resolveSpritesheet(manifest.spritesheetPath, in: directory) else { return nil }
        guard hasValidAtlasDimensions(at: spritesheetURL) else {
            logger.error("Pet package \(manifest.id) rejected: invalid atlas dimensions")
            return nil
        }
        return PetPackage(
            id: manifest.id,
            displayName: manifest.displayName,
            description: manifest.description,
            directoryURL: directory,
            spritesheetURL: spritesheetURL,
            source: source
        )
    }

    private static func decodeManifest(at url: URL) -> PetPackageManifest? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size <= maxManifestBytes,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(PetPackageManifest.self, from: data)
    }

    private static func resolveSpritesheet(_ path: String, in directory: URL) -> URL? {
        guard !path.contains("://") else { return nil }
        let candidate = directory.appendingPathComponent(path).standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath()
        let base = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path == base.path || resolved.path.hasPrefix(base.path + "/") else { return nil }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: resolved.path),
              let attributes = try? fileManager.attributesOfItem(atPath: resolved.path),
              let size = attributes[.size] as? Int, size <= maxSpritesheetBytes
        else { return nil }
        return resolved
    }

    private static func hasValidAtlasDimensions(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        return width == PetAtlas.width && height == PetAtlas.height
    }
}
