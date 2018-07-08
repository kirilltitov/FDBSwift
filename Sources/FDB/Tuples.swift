public protocol TuplePackable {
    func pack() -> Bytes
    func _pack() -> Bytes
}

public extension TuplePackable {
    public func _pack() -> Bytes {
        return self.pack()
    }
}

let NULL: Byte                = 0x00
let PREFIX_BYTE_STRING: Byte  = 0x01
let PREFIX_UTF_STRING: Byte   = 0x02
let PREFIX_NESTED_TUPLE: Byte = 0x05

let NULL_ESCAPE_SEQUENCE: Bytes = [NULL, 0xFF]

public struct Null: TuplePackable {
    public func pack() -> Bytes {
        return [NULL]
    }
}

extension String: TuplePackable {
    public func pack() -> Bytes {
        var result = Bytes()
        result.append(PREFIX_UTF_STRING)
        Bytes(self.utf8).forEach {
            if $0 == NULL {
                result.append(contentsOf: NULL_ESCAPE_SEQUENCE)
            } else {
                result.append($0)
            }
        }
        result.append(NULL)
        return result
    }
}

extension Array: TuplePackable where Element == Byte {
    public func pack() -> Bytes {
        var result = Bytes()
        result.append(PREFIX_BYTE_STRING)
        self.forEach {
            if $0 == NULL {
                result.append(contentsOf: NULL_ESCAPE_SEQUENCE)
            } else {
                result.append($0)
            }
        }
        result.append(NULL)
        return result
    }
}

public struct Tuple: TuplePackable {
    private let tuple: [TuplePackable?]

    public init(_ input: TuplePackable?...) {
        self.tuple = input
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
            result.append(contentsOf: value.pack())
        }
        result.append(NULL)
        return result
    }
}
