import UIKit

struct Person: Identifiable {
    let id: Int
    let name: String
    /// The asset catalog image `friend-<id>`, softened for its bubble.
    let softPhoto: UIImage?

    init(id: Int, name: String) {
        self.id = id
        self.name = name
        self.softPhoto = UIImage(named: "friend-\(id)").map { SoftPhoto.render($0, diameter: 240) }
    }

    var initials: String {
        String(name.split(separator: " ").compactMap(\.first))
    }
}

extension Person {
    /// Ids 1...8 match the bubbles in `OrbitChoreography`: you, the friend you bump, then everyone else.
    static let samples: [Person] = [
        "Maya", "Kwame", "Ines", "Kai", "Amara", "Theo", "Priya", "Omar",
    ].enumerated().map { index, name in
        Person(id: index + 1, name: name)
    }
}
