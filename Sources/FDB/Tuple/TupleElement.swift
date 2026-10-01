#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension FDB {
    /// A dynamically typed element of a ``FDB/Tuple``.
    ///
    /// Use it when the structure of a tuple is not known in advance, otherwise prefer typed
    /// ``FDB/Tuple/unpack(as:)``.
    public enum TupleElement: Hashable, Sendable {
        case null
        case bytes(Bytes)
        case string(String)
        case tuple(FDB.Tuple)
        /// Any integer which fits into `Int64`
        case int(Int64)
        /// Integer in `Int64.max + 1 ... UInt64.max` range
        case uint(UInt64)
        case float(Float)
        case double(Double)
        case bool(Bool)
        case uuid(UUID)
        case versionstamp(FDB.Versionstamp)
    }

    /// A `null` tuple element
    public struct Null: Hashable, Sendable {
        public init() {}
    }
}

extension FDB {
    /// A value which can be encoded as an element of ``FDB/Tuple``
    public protocol TuplePackable: Sendable {
        func pack(into encoder: inout FDB.TupleEncoder)
    }

    /// A value which can be decoded from an element of ``FDB/Tuple``
    public protocol TupleUnpackable {
        init(tupleElement: FDB.TupleElement) throws(FDB.Error)
    }

    public typealias TupleCodable = TuplePackable & TupleUnpackable
}

// MARK: - Conformances

extension FDB.TupleElement: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        switch self {
        case .null: encoder.appendNull()
        case let .bytes(value): encoder.appendBytes(value)
        case let .string(value): encoder.appendString(value)
        case let .tuple(value): encoder.appendNested(value)
        case let .int(value): encoder.appendInt(value)
        case let .uint(value): encoder.appendUInt(value)
        case let .float(value): encoder.appendFloat(value)
        case let .double(value): encoder.appendDouble(value)
        case let .bool(value): encoder.appendBool(value)
        case let .uuid(value): encoder.appendUUID(value)
        case let .versionstamp(value): encoder.appendVersionstamp(value)
        }
    }

    public init(tupleElement: FDB.TupleElement) {
        self = tupleElement
    }
}

extension FDB.Null: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendNull()
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard case .null = tupleElement else { throw .unpackTypeMismatch }
    }
}

extension Optional: FDB.TuplePackable where Wrapped: FDB.TuplePackable {
    /// `nil` is encoded as `null`
    public func pack(into encoder: inout FDB.TupleEncoder) {
        switch self {
        case .none: encoder.appendNull()
        case let .some(value): value.pack(into: &encoder)
        }
    }
}

extension Optional: FDB.TupleUnpackable where Wrapped: FDB.TupleUnpackable {
    /// `null` is decoded as `nil`
    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        if case .null = tupleElement {
            self = .none
        } else {
            self = .some(try Wrapped(tupleElement: tupleElement))
        }
    }
}

extension Array: FDB.TuplePackable where Element == UInt8 {
    /// Bytes are encoded as a byte string
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendBytes(self)
    }
}

extension Array: FDB.TupleUnpackable where Element == UInt8 {
    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard case let .bytes(value) = tupleElement else { throw .unpackTypeMismatch }
        self = value
    }
}

extension String: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendString(self)
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard case let .string(value) = tupleElement else { throw .unpackTypeMismatch }
        self = value
    }
}

extension Bool: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendBool(self)
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard case let .bool(value) = tupleElement else { throw .unpackTypeMismatch }
        self = value
    }
}

extension Float: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendFloat(self)
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard case let .float(value) = tupleElement else { throw .unpackTypeMismatch }
        self = value
    }
}

extension Double: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendDouble(self)
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard case let .double(value) = tupleElement else { throw .unpackTypeMismatch }
        self = value
    }
}

extension UUID: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendUUID(self)
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard case let .uuid(value) = tupleElement else { throw .unpackTypeMismatch }
        self = value
    }
}

extension FDB.Versionstamp: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendVersionstamp(self)
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard case let .versionstamp(value) = tupleElement else { throw .unpackTypeMismatch }
        self = value
    }
}

extension FDB.Tuple: FDB.TupleCodable {
    /// Tuple is encoded as a nested tuple
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendNested(self)
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard case let .tuple(value) = tupleElement else { throw .unpackTypeMismatch }
        self = value
    }
}

// MARK: Integers

extension FDB {
    /// All fixed-width integers up to 64 bits are encoded the same way and are interchangeable when decoding
    /// (as long as the value fits into the requested type)
    public protocol TupleInteger: FixedWidthInteger, TupleCodable {}
}

public extension FDB.TupleInteger {
    func pack(into encoder: inout FDB.TupleEncoder) {
        if Self.isSigned {
            encoder.appendInt(Int64(self))
        } else {
            encoder.appendUInt(UInt64(self))
        }
    }

    init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        let result: Self?
        switch tupleElement {
        case let .int(value): result = Self(exactly: value)
        case let .uint(value): result = Self(exactly: value)
        default: throw .unpackTypeMismatch
        }
        guard let result else { throw .unpackTooLargeInt }
        self = result
    }
}

extension Int: FDB.TupleInteger {}
extension Int8: FDB.TupleInteger {}
extension Int16: FDB.TupleInteger {}
extension Int32: FDB.TupleInteger {}
extension Int64: FDB.TupleInteger {}
extension UInt: FDB.TupleInteger {}
extension UInt16: FDB.TupleInteger {}
extension UInt32: FDB.TupleInteger {}
extension UInt64: FDB.TupleInteger {}
// `UInt8` is intentionally not here: `[UInt8]` is a byte string, and a lone byte is ambiguous enough to be explicit
