import Foundation

/// User-defined items that can appear in the taskbar in addition to windows/pinned apps.
///
/// JSON shape (example):
/// ```json
/// { "type": "link", "id": "…", "title": "GitHub", "url": "https://github.com", "icon": "sf:link" }
/// ```
enum CustomItem: Codable, Sendable, Equatable {
    case spacer(id: String, width: Int)
    case text(id: String, text: String)
    case link(id: String, title: String, url: String, icon: String?)
    case folder(id: String, title: String, path: String, icon: String?)

    enum ItemType: String, Codable, Sendable {
        case spacer
        case text
        case link
        case folder
    }

    static func makeId() -> String {
        UUID().uuidString
    }

    var id: String {
        switch self {
        case .spacer(let id, _): id
        case .text(let id, _): id
        case .link(let id, _, _, _): id
        case .folder(let id, _, _, _): id
        }
    }

    var type: ItemType {
        switch self {
        case .spacer: .spacer
        case .text: .text
        case .link: .link
        case .folder: .folder
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case width
        case text
        case title
        case url
        case path
        case icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(ItemType.self, forKey: .type)
        let id = try c.decodeIfPresent(String.self, forKey: .id) ?? Self.makeId()

        switch type {
        case .spacer:
            let width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 12
            self = .spacer(id: id, width: width)
        case .text:
            let text = try c.decode(String.self, forKey: .text)
            self = .text(id: id, text: text)
        case .link:
            let title = try c.decode(String.self, forKey: .title)
            let url = try c.decode(String.self, forKey: .url)
            let icon = try c.decodeIfPresent(String.self, forKey: .icon)
            self = .link(id: id, title: title, url: url, icon: icon)
        case .folder:
            let title = try c.decode(String.self, forKey: .title)
            let path = try c.decode(String.self, forKey: .path)
            let icon = try c.decodeIfPresent(String.self, forKey: .icon)
            self = .folder(id: id, title: title, path: path, icon: icon)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)

        switch self {
        case .spacer(_, let width):
            try c.encode(width, forKey: .width)
        case .text(_, let text):
            try c.encode(text, forKey: .text)
        case .link(_, let title, let url, let icon):
            try c.encode(title, forKey: .title)
            try c.encode(url, forKey: .url)
            try c.encodeIfPresent(icon, forKey: .icon)
        case .folder(_, let title, let path, let icon):
            try c.encode(title, forKey: .title)
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(icon, forKey: .icon)
        }
    }
}

