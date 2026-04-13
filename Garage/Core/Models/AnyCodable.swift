import Foundation

struct AnyCodable: Codable, Equatable, Sendable {
    let value: CodableValue

    init(_ value: some Sendable) {
        self.value = CodableValue(value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = .string(string)
        } else if let int = try? container.decode(Int.self) {
            value = .int(int)
        } else if let double = try? container.decode(Double.self) {
            value = .double(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = .bool(bool)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = .dictionary(dictionary)
        } else if let array = try? container.decode([AnyCodable].self) {
            value = .array(array)
        } else {
            value = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .string(let string):
            try container.encode(string)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .bool(let bool):
            try container.encode(bool)
        case .dictionary(let dictionary):
            try container.encode(dictionary)
        case .array(let array):
            try container.encode(array)
        case .null:
            try container.encodeNil()
        }
    }
}

enum CodableValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: AnyCodable])
    case array([AnyCodable])
    case null

    init(_ value: some Sendable) {
        switch value {
        case let value as String:
            self = .string(value)
        case let value as Int:
            self = .int(value)
        case let value as Double:
            self = .double(value)
        case let value as Bool:
            self = .bool(value)
        case let value as [String: AnyCodable]:
            self = .dictionary(value)
        case let value as [AnyCodable]:
            self = .array(value)
        default:
            self = .null
        }
    }
}

extension CodableValue {
    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        case .string(let value):
            return Double(value)
        default:
            return nil
        }
    }
}
