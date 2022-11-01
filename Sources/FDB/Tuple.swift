import Helpers

/// A type-erased Tuple packable protocol
///
/// You may adopt this protocol with any of your custom types.
/// You should only implement `getPackedFDBTupleValue()` method, not `_getPackedFDBTupleValue()`.
/// Obviously, in most cases you would like to treat your
/// class/struct as binary string, this is why simply returning
/// bytes of your internal value representation is incorrect,
/// because noone would know that your returned byte array
/// should actually be treated as a binary string.
/// It must be wrapped with control characters first.
/// This is why you should additionally call .getPackedFDBTupleValue() from your
/// resulting byte array (see Tuple+Array.swift). Otherwise packing
/// will be incorrect and will fail with an error.
/// Example of custom getPackedFDBTupleValue() implementation:
/// ```
/// extension MyValue: FDBTuplePackable {
///     func getPackedFDBTupleValue() -> Bytes {
///         self
///             .getBytesSomehow() // your method returns [UInt8]
///             .getPackedFDBTupleValue() // this will wrap your bytes
///                                       // with tuple binary string magic :)
///     }
/// }
/// ```
public protocol FDBTuplePackable {
    /// Returns self bytes representation wrapped with control bytes.
    func getPackedFDBTupleValue() -> Bytes

    /// Internal method extending `getPackedFDBTupleValue` method with more complicated logic, you ought not implement it.
    func _getPackedFDBTupleValue() -> Bytes
}

public extension FDBTuplePackable {
    func _getPackedFDBTupleValue() -> Bytes {
        self.getPackedFDBTupleValue()
    }
}


internal extension FDB.Tuple {
    static let NULL = Byte(0x00)
    static let NULL_ESCAPE_SEQUENCE: Bytes = [NULL, 0xFF]

    enum Prefix {
        static let BYTE_STRING          = Byte(0x01)
        static let UTF_STRING           = Byte(0x02)
        static let NESTED_TUPLE         = Byte(0x05)
        static let INT_ZERO_CODE        = Byte(0x14)
        static let POS_INT_END          = Byte(0x1D)
        static let NEG_INT_START        = Byte(0x0B)
        static let FLOAT                = Byte(0x20)
        static let DOUBLE               = Byte(0x21)
        static let LONG_DOUBLE          = Byte(0x22)
        static let BOOL_FALSE           = Byte(0x26)
        static let BOOL_TRUE            = Byte(0x27)
        static let UUID                 = Byte(0x30)
        static let VERSIONSTAMP_80BIT   = Byte(0x32)
        static let VERSIONSTAMP_96BIT   = Byte(0x33)
    }
}

public extension FDB {
    /// Tuple layer implementation. Stores an ordered collection of `FDBTuplePackable` items.
    struct Tuple: FDBTuplePackable {
        public private(set) var tuple: [FDBTuplePackable]

        public init(_ input: [FDBTuplePackable]) {
            self.tuple = input
        }

        public init(_ input: FDBTuplePackable...) {
            self.init(input)
        }

        public func getPackedFDBTupleValue() -> Bytes {
            var result = Bytes()
            self.tuple.forEach {
                result.append(contentsOf: $0._getPackedFDBTupleValue())
            }
            return result
        }

        public func _getPackedFDBTupleValue() -> Bytes {
            var result = Bytes()
            result.append(Prefix.NESTED_TUPLE)
            self.tuple.forEach {
                if $0 is Null {
                    result.append(contentsOf: Tuple.NULL_ESCAPE_SEQUENCE)
                } else {
                    result.append(contentsOf: $0._getPackedFDBTupleValue())
                }
            }
            result.append(Tuple.NULL)
            return result
        }
    }

    /// Represents `NULL` Tuple value.
    struct Null: FDBTuplePackable {
        public func getPackedFDBTupleValue() -> Bytes {
            [Tuple.NULL]
        }
    }
}

extension FDB.Tuple: FDBKey {
    public func asFDBKey() -> Bytes {
        self.getPackedFDBTupleValue()
    }
}

// I DON'T LIKE IT SO MUCH
extension FDB.Tuple: Hashable {
    public static func == (lhs: FDB.Tuple, rhs: FDB.Tuple) -> Bool {
        lhs.getPackedFDBTupleValue() == rhs.getPackedFDBTupleValue()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.getPackedFDBTupleValue())
    }
}
