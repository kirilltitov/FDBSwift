public protocol TuplePackable {
    func pack() -> Bytes
    func _pack() -> Bytes
}

public extension TuplePackable {
    public func _pack() -> Bytes {
        return self.pack()
    }
}

internal let NULL: Byte                 = 0x00
internal let PREFIX_BYTE_STRING: Byte   = 0x01
internal let PREFIX_UTF_STRING: Byte    = 0x02
internal let PREFIX_NESTED_TUPLE: Byte  = 0x05
internal let PREFIX_INT_ZERO_CODE: Byte = 0x14
internal let PREFIX_POS_INT_END: Byte   = 0x1d
internal let PREFIX_NEG_INT_START: Byte = 0x0b

internal let NULL_ESCAPE_SEQUENCE: Bytes = [NULL, 0xFF]

public struct Null: TuplePackable {
    public func pack() -> Bytes {
        return [NULL]
    }
}

public struct Tuple: TuplePackable {
    public private(set) var tuple: [TuplePackable?]

    public init(_ input: [TuplePackable?]) {
        self.tuple = input
    }

    public init(_ input: TuplePackable?...) {
        self.init(input)
    }

    public func pack() -> Bytes {
        var result = Bytes()
        self.tuple.forEach {
            guard let value = $0 else {
                result.append(NULL)
                return
            }
            result.append(contentsOf: value._pack())
        }
        return result
    }

    public func _pack() -> Bytes {
        var result = Bytes()
        result.append(PREFIX_NESTED_TUPLE)
        self.tuple.forEach {
            guard let value = $0 else {
                result.append(contentsOf: NULL_ESCAPE_SEQUENCE)
                return
            }
            result.append(contentsOf: value._pack())
        }
        result.append(NULL)
        return result
    }
}
