import UIKit

struct Person: Identifiable {
    let id: Int
    let name: String
    /// The asset catalog image `friend-<id>`, softened for its bubble.
    let softPhoto: UIImage?

    init(id: Int, name: String) {
        self.id = id
        self.name = name
        self.softPhoto = UIImage(named: "friend-\(id)").map { SoftPhoto.render($0, diameter: 150) }
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
