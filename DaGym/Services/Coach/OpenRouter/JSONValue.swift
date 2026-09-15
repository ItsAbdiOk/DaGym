import Foundation

extension OpenRouterWire {
    /// Any JSON document, Codable without `[String: Any]`. Carries the tool parameter schemas
    /// through `ToolDefinition` untouched, whatever struct GymCore's catalogue built them from.
    indirect enum JSONValue: Codable, Equatable, Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case object([String: JSONValue])
        case array([JSONValue])
        case null

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let bool = try? container.decode(Bool.self) {
                self = .bool(bool)
            } else if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else if let array = try? container.decode([JSONValue].self) {
                self = .array(array)
            } else if let object = try? container.decode([String: JSONValue].self) {
                self = .object(object)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not JSON")
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let string): try container.encode(string)
            case .number(let number):
                // Whole numbers go out as integers so `"minimum": 1` doesn't become `1.0`.
                if number == number.rounded(), abs(number) < 1e15 {
                    try container.encode(Int(number))
                } else {
                    try container.encode(number)
                }
            case .bool(let bool): try container.encode(bool)
            case .object(let object): try container.encode(object)
            case .array(let array): try container.encode(array)
            case .null: try container.encodeNil()
            }
        }

        subscript(key: String) -> JSONValue? {
            guard case .object(let object) = self else { return nil }
            return object[key]
        }

        var stringValue: String? {
            guard case .string(let string) = self else { return nil }
            return string
        }
    }
}
