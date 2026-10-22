import UIKit

struct Person: Identifiable {
    let id: Int
    let name: String
    /// The asset catalog image `friend-<id>`, as is (the glass orb shader works on it directly).
    let photo: UIImage?
    /// The same photo under a feathered mask, for `PhotoStyle.mask`.
    let softPhoto: UIImage?

    init(id: Int, name: String) {
        self.id = id
        self.name = name
        let image = UIImage(named: "friend-\(id)")
        self.photo = image
        self.softPhoto = image.map { SoftPhoto.render($0, diameter: 240) }
    }

    var initials: String {
        String(name.split(separator: " ").compactMap(\.first))
    }
}

extension Person {
    /// Ids 1...9 match the bubbles in `OrbitChoreography`: you, the friend you bump, then everyone else.
    static let samples: [Person] = [
        "Maya", "Kwame", "Ines", "Kai", "Amara", "Theo", "Priya", "Omar", "Lena",
    ].enumerated().map { index, name in
        Person(id: index + 1, name: name)
    }
}
