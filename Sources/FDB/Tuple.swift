/// A type-erased Tuple packable protocol
///
/// You may adopt this protocol with any of your custom types.
/// You should only implement pack() method, not _pack().
/// Obviously, in most cases you would like to treat your
/// class/struct as binary string, this is why simply returning
/// bytes of your internal value representation is incorrect,
/// because noone would know that your returned byte array
/// should actually be treated as a binary string.
/// It must be wrapped with control characters first.
/// This is why you should additionally call .pack() from your
/// resulting byte array (see Tuple+Array.swift). Otherwise packing
/// will be incorrect and will fail with an error.
/// Example of custom pack() implementation:
/// ```
/// extension MyValue: FDBTuplePackable {
///     func pack() -> Bytes {
///         self
///             .getBytesSomehow() // your method returns [UInt8]
///             .pack()            // this will wrap your bytes
///                                // with tuple binary string magic :)
///     }
/// }
/// ```
public protocol FDBTuplePackable {
    /// Returns self bytes representation wrapped with control bytes.
    func pack() -> Bytes

    /// Internal method extending `pack` method with more complicated logic, you ought not implement it.
    func _pack() -> Bytes
}

public extension FDBTuplePackable {
    func _pack() -> Bytes {
        return self.pack()
    }
}


internal extension FDB.Tuple {
    static let NULL = Byte(0x00)
    static let NULL_ESCAPE_SEQUENCE: Bytes = [NULL, 0xFF]

    enum Prefix {
        static let BYTE_STRING   = Byte(0x01)
        static let UTF_STRING    = Byte(0x02)
        static let NESTED_TUPLE  = Byte(0x05)
        static let INT_ZERO_CODE = Byte(0x14)
        static let POS_INT_END   = Byte(0x1D)
        static let NEG_INT_START = Byte(0x0B)
        static let FLOAT         = Byte(0x20)
        static let DOUBLE        = Byte(0x21)
        static let LONG_DOUBLE   = Byte(0x22)
        static let BOOL_FALSE    = Byte(0x26)
        static let BOOL_TRUE     = Byte(0x27)
        static let UUID          = Byte(0x30)
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

        public func pack() -> Bytes {
            var result = Bytes()
            self.tuple.forEach {
                result.append(contentsOf: $0._pack())
            }
            return result
        }

        public func _pack() -> Bytes {
            var result = Bytes()
            result.append(Prefix.NESTED_TUPLE)
            self.tuple.forEach {
                if $0 is Null {
                    result.append(contentsOf: Tuple.NULL_ESCAPE_SEQUENCE)
                } else {
                    result.append(contentsOf: $0._pack())
                }
            }
            result.append(Tuple.NULL)
            return result
        }
    }

    /// Represents `NULL` Tuple value.
    struct Null: FDBTuplePackable {
        public func pack() -> Bytes {
            return [Tuple.NULL]
        }
    }
}

extension FDB.Tuple: AnyFDBKey {
    public func asFDBKey() -> Bytes {
        return self.pack()
    }
}

// I DON'T LIKE IT SO MUCH
extension FDB.Tuple: Hashable {
    public static func == (lhs: FDB.Tuple, rhs: FDB.Tuple) -> Bool {
        return lhs.pack() == rhs.pack()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.pack())
    }
}
