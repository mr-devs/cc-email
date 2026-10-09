import Foundation

/// A JSON value. The stream-json protocol is loosely typed and grows new fields often,
/// so events are decoded into this and read with optional subscripts instead of Codable structs.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Reading

    public subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let items) = self, items.indices.contains(index) { return items[index] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    public var intValue: Int? { doubleValue.map { Int($0) } }

    public var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    public var isNull: Bool { self == .null }

    // MARK: Conversion

    /// Converts the output of `JSONSerialization`.
    public init(any value: Any) {
        switch value {
        case let n as NSNumber:
            // NSNumber bridges both booleans and numbers; tell them apart by type ID.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map(JSONValue.init(any:)))
        case let d as [String: Any]: self = .object(d.mapValues(JSONValue.init(any:)))
        default: self = .null
        }
    }

    /// A value `JSONSerialization` can write.
    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { return Int(n) }
            return n
        case .string(let s): return s
        case .array(let items): return items.map(\.anyValue)
        case .object(let dict): return dict.mapValues(\.anyValue)
        }
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        JSONValue(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    public static func parse(_ string: String) throws -> JSONValue {
        try parse(Data(string.utf8))
    }

    /// Compact JSON with no newlines, suitable for one NDJSON line.
    public func serialized(sortedKeys: Bool = false, pretty: Bool = false) -> String {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes]
        if sortedKeys { options.insert(.sortedKeys) }
        if pretty { options.insert(.prettyPrinted) }
        guard let data = try? JSONSerialization.data(withJSONObject: anyValue, options: options) else {
            return "null"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}
