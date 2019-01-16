public struct Subspace {
    public let prefix: Bytes
    public let itemsCount: Int

    public var range: RangeFDBKey {
        return (
            begin: self.prefix + [0],
            end: self.prefix + [255]
        )
    }

    public init(_ prefix: Bytes, items: Int = 1) {
        self.prefix = prefix
        self.itemsCount = items
    }

    public init(_ input: TuplePackable?...) {
        self.init(Tuple(input), items: input.count)
    }

    public init(_ tuple: Tuple, items: Int = 1) {
        self.init(tuple.pack(), items: items)
    }

    public func subspace(_ input: [TuplePackable?]) -> Subspace {
        return Subspace(self.prefix + Tuple(input).pack(), items: self.itemsCount + input.count)
    }

    public func subspace(_ input: TuplePackable?...) -> Subspace {
        return self.subspace(input)
    }

    public subscript(index: TuplePackable?...) -> Subspace {
        return self.subspace(index)
    }
}
