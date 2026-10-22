import UIKit

struct Person: Identifiable {
    let id: Int
    let name: String
    /// From the asset catalog image `friend-<id>`.
    let photo: UIImage?

    init(id: Int, name: String) {
        self.id = id
        self.name = name
        self.photo = UIImage(named: "friend-\(id)")
    }

    var initials: String {
        String(name.split(separator: " ").compactMap(\.first))
    }
}

extension Person {
    /// Ids 1...10 match the friend bubbles in `OrbitChoreography`.
    static let samples: [Person] = [
        "Maya", "Kwame", "Ines", "Kai", "Amara",
        "Theo", "Priya", "Omar", "Sofia", "Lucas",
    ].enumerated().map { index, name in
        Person(id: index + 1, name: name)
    }
}
