import Foundation

enum PetSettings {
    enum Key {
        static let enabled = "muxy.pet.enabled"
        static let selectedID = "muxy.pet.selectedID"
        static let size = "muxy.pet.size"
        static let offsetX = "muxy.pet.offsetX"
        static let offsetY = "muxy.pet.offsetY"
    }

    enum Default {
        static let enabled = true
        static let selectedID = "banana-cat"
        static let size: Double = 112
    }

    static let minSize: Double = 72
    static let maxSize: Double = 160
}
