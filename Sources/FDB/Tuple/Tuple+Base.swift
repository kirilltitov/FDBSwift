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
/// will be incorrect, but most importantly - unpacking will
/// fail with a fatal error.
/// Example of custom pack() implementation:
/// ```
/// extension MyValue: FDBTuplePackable {
///     public func pack() -> Bytes {
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
    public func _pack() -> Bytes {
        return self.pack()
    }
}

internal let NULL: Byte                 = 0x00
internal let PREFIX_BYTE_STRING: Byte   = 0x01
internal let PREFIX_UTF_STRING: Byte    = 0x02
internal let PREFIX_NESTED_TUPLE: Byte  = 0x05
internal let PREFIX_INT_ZERO_CODE: Byte = 0x14
internal let PREFIX_POS_INT_END: Byte   = 0x1D
internal let PREFIX_NEG_INT_START: Byte = 0x0B

internal let NULL_ESCAPE_SEQUENCE: Bytes = [NULL, 0xFF]

public extension FDB {
    /// Represents `NULL` Tuple value.
    public struct Null: FDBTuplePackable {
        public func pack() -> Bytes {
            return [NULL]
        }
    }

    /// Tuple layer implementation. Stores an ordered collection of `FDBTuplePackable` items.
    public struct Tuple: FDBTuplePackable {
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
            result.append(PREFIX_NESTED_TUPLE)
            self.tuple.forEach {
                if $0 is Null {
                    result.append(contentsOf: NULL_ESCAPE_SEQUENCE)
                } else {
                    result.append(contentsOf: $0._pack())
                }
            }
            result.append(NULL)
            return result
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
