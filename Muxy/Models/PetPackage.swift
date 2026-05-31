import Foundation

struct PetPackage: Identifiable, Equatable {
    enum Source: String {
        case bundled
        case codexCustom
        case muxyCustom
    }

    let id: String
    let displayName: String
    let description: String
    let directoryURL: URL
    let spritesheetURL: URL
    let source: Source
}

struct PetPackageManifest: Decodable {
    let id: String
    let displayName: String
    let description: String
    let spritesheetPath: String
}
