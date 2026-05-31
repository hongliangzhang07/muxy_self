import Foundation

enum PetSettings {
    enum Key {
        static let enabled = "muxy.pet.enabled"
        static let selectedID = "muxy.pet.selectedID"
        static let size = "muxy.pet.size"
    }

    enum Default {
        static let enabled = true
        static let selectedID = "orange-crab"
        static let size: Double = 112
    }

    static let minSize: Double = 72
    static let maxSize: Double = 160
}
