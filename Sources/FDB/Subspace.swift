public struct Subspace {
    public let prefix: Bytes

    public var range: RangeFDBKey {
        return (
            begin: self.prefix + [0],
            end: self.prefix + [255]
        )
    }

    public init(_ prefix: Bytes) {
        self.prefix = prefix
    }

    public init(_ input: TuplePackable?...) {
        self.init(Tuple(input))
    }

    public init(_ tuple: Tuple) {
        self.init(tuple.pack())
    }

    public func subspace(_ input: TuplePackable?...) -> Subspace {
        return Subspace(self.prefix + Tuple(input).pack())
    }
}
