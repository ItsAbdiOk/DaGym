import Foundation

// `String(decoding:as:)` is deliberate: corrupted bytes are the point, and the failable
// initializer would turn every invalid-UTF-8 case into a skipped iteration.
// swiftlint:disable optional_data_string_conversion

// Shared plumbing for the `Fuzz*` suites: a seeded xorshift generator (so a failing iteration is
// reproducible from its seed and index), a tiny JSON tree that can render tokens `JSONSerialization`
// refuses (NaN, `-0`, `1e999`), and the mutation vocabulary each suite draws from.

/// xorshift64*: deterministic, no Foundation randomness. Seed 0 is mapped to a fixed non-zero
/// state since xorshift is stuck at 0.
struct FuzzRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    /// 0..<bound.
    mutating func int(_ bound: Int) -> Int {
        precondition(bound > 0)
        return Int(next() % UInt64(bound))
    }

    mutating func bool() -> Bool { next() & 1 == 1 }

    mutating func pick<T>(_ items: [T]) -> T { items[int(items.count)] }
}

/// A JSON tree whose leaves are raw token text, so a mutation can emit `NaN`, `-0`, `1e999` or a
/// bare `Infinity` — everything a hand-edited file might carry and `JSONSerialization` won't write.
indirect enum FuzzJSON {
    case object([(String, FuzzJSON)])
    case array([FuzzJSON])
    case string(String)
    case raw(String)

    static let null = FuzzJSON.raw("null")

    /// Converts a `JSONSerialization` tree (from a valid encoded fixture).
    init(any: Any) {
        switch any {
        case let dictionary as [String: Any]:
            self = .object(dictionary.keys.sorted().map { ($0, FuzzJSON(any: dictionary[$0] as Any)) })
        case let array as [Any]:
            self = .array(array.map(FuzzJSON.init(any:)))
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .raw(number.boolValue ? "true" : "false")
            } else {
                self = .raw(number.stringValue)
            }
        case is NSNull:
            self = .null
        default:
            self = .raw(String(describing: any))
        }
    }

    func render() -> String {
        switch self {
        case .object(let members):
            return "{" + members.map { "\(Self.quote($0.0)):\($0.1.render())" }.joined(separator: ",") + "}"
        case .array(let items):
            return "[" + items.map { $0.render() }.joined(separator: ",") + "]"
        case .string(let text):
            return Self.quote(text)
        case .raw(let token):
            return token
        }
    }

    private static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Every path to a member/element in the tree, so a mutation can pick one uniformly.
    func paths(prefix: [FuzzPath] = []) -> [[FuzzPath]] {
        var result: [[FuzzPath]] = prefix.isEmpty ? [] : [prefix]
        switch self {
        case .object(let members):
            for (key, value) in members { result += value.paths(prefix: prefix + [.key(key)]) }
        case .array(let items):
            for (index, value) in items.enumerated() {
                result += value.paths(prefix: prefix + [.index(index)])
            }
        case .string, .raw:
            break
        }
        return result
    }

    func replacing(path: [FuzzPath], with transform: (FuzzJSON) -> FuzzJSON?) -> FuzzJSON {
        guard let head = path.first else { return transform(self) ?? self }
        let rest = Array(path.dropFirst())
        switch (self, head) {
        case (.object(let members), .key(let key)):
            return .object(members.compactMap { name, value in
                guard name == key else { return (name, value) }
                return Self.step(value, rest: rest, transform).map { (name, $0) }
            })
        case (.array(let items), .index(let index)):
            return .array(items.enumerated().compactMap { position, value in
                position == index ? Self.step(value, rest: rest, transform) : value
            })
        default:
            return self
        }
    }

    /// The matched node: replaced (or deleted, on `nil`) at the end of the path, recursed otherwise.
    private static func step(
        _ value: FuzzJSON, rest: [FuzzPath], _ transform: (FuzzJSON) -> FuzzJSON?
    ) -> FuzzJSON? {
        rest.isEmpty ? transform(value) : value.replacing(path: rest, with: transform)
    }

    /// Appends an extra member to the first object on `path` (or the root when empty).
    func addingExtraKey(_ key: String, value: FuzzJSON) -> FuzzJSON {
        guard case .object(let members) = self else { return self }
        return .object(members + [(key, value)])
    }
}

enum FuzzPath: Equatable {
    case key(String)
    case index(Int)
}

/// The hostile-value vocabulary. Every case is a leaf token or a small subtree; `pick` returns
/// one chosen by the generator so a failing iteration names exactly what it substituted.
enum FuzzValues {
    static let hugeStringLength = 10 * 1024 * 1024

    static let numberTokens: [String] = [
        "1e308", "-1e308", "1e309", "-1e309", "NaN", "-0", "0", "-1", "9223372036854775807",
        "9223372036854775808", "-9223372036854775808", "-9223372036854775809",
        "1.7976931348623157e308", "4.9e-324", "5e-324", "1e-300", "0.5", "-0.5", "Infinity", "-Infinity",
        "1e400", "99999999999999999999"
    ]

    static let stringTokens: [String] = [
        "", " ", "\n", "\u{0}", "sprint", "not-a-uuid", "00000000-0000-0000-0000-000000000000",
        "2024-13-45T99:99:99Z", "not a date", "🏋️", String(repeating: "x", count: 130),
        String(repeating: "y", count: 2100), "\u{FEFF}", "\\u0000", "{\"nested\":true}", "1e999", "nan"
    ]

    /// A leaf replacement for the node at a path: wrong type, hostile number, hostile string,
    /// null, deep nesting, or (rarely) a 10 MB string.
    static func leaf(_ rng: inout FuzzRNG, allowHuge: Bool) -> FuzzJSON {
        let makers: [(inout FuzzRNG) -> FuzzJSON] = [
            { .raw($0.pick(numberTokens)) },
            { .string($0.pick(stringTokens)) },
            { _ in .null },
            { .raw($0.bool() ? "true" : "false") },
            { _ in .array([]) },
            { _ in .object([]) },
            { deep(depth: 40 + $0.int(200)) },
            { .array([.raw($0.pick(numberTokens)), .string($0.pick(stringTokens))]) },
            { .string($0.pick(numberTokens)) },
            { .raw($0.pick(numberTokens)) },
            { .string($0.pick(stringTokens)) },
            { _ in .string(String(repeating: "z", count: hugeStringLength)) }
        ]
        let choice = rng.int(allowHuge ? makers.count : makers.count - 1)
        return makers[choice](&rng)
    }

    static func deep(depth: Int) -> FuzzJSON {
        var node = FuzzJSON.raw("1")
        for _ in 0..<depth { node = .array([node]) }
        return node
    }
}

/// Byte-level corruptions applied to rendered text: truncation at a random offset, invalid UTF-8
/// injection, a BOM, CRLF, and the empty file.
enum FuzzBytes {
    static func corrupt(_ data: Data, _ rng: inout FuzzRNG) -> Data {
        let bytes = [UInt8](data)
        let corruptions: [([UInt8], inout FuzzRNG) -> [UInt8]] = [
            { bytes, rng in Array(bytes.prefix(bytes.isEmpty ? 0 : rng.int(bytes.count))) },
            { bytes, rng in
                var out = bytes
                let at = bytes.isEmpty ? 0 : rng.int(bytes.count)
                out.insert(contentsOf: [0xFF, 0xFE, 0xC0, 0x80, 0xED, 0xA0, 0x80], at: at)
                return out
            },
            { bytes, _ in [0xEF, 0xBB, 0xBF] + bytes },
            { bytes, _ in
                let text = String(decoding: bytes, as: UTF8.self)
                return Array(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
            },
            { _, _ in [] },
            { bytes, rng in
                var out = bytes
                for _ in 0..<(1 + rng.int(8)) where !out.isEmpty {
                    out[rng.int(out.count)] = UInt8(rng.int(256))
                }
                return out
            }
        ]
        let choice = rng.int(corruptions.count)
        return Data(corruptions[choice](bytes, &rng))
    }
}

// swiftlint:enable optional_data_string_conversion
