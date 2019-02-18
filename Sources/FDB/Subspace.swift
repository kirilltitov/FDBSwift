public extension FDB {
    public struct Subspace {
        public let prefix: Bytes
        public let itemsCount: Int
        
        public var range: FDB.RangeKey {
            return (
                begin: self.prefix + [0],
                end: self.prefix + [255]
            )
        }
        
        public init(_ prefix: Bytes, items: Int = 1) {
            self.prefix = prefix
            self.itemsCount = items
        }
        
        public init(_ input: FDBTuplePackable...) {
            self.init(Tuple(input), items: input.count)
        }
        
        public init(_ tuple: Tuple, items: Int = 1) {
            self.init(tuple.pack(), items: items)
        }
        
        public func subspace(_ input: [FDBTuplePackable]) -> Subspace {
            return Subspace(self.prefix + Tuple(input).pack(), items: self.itemsCount + input.count)
        }
        
        public func subspace(_ input: FDBTuplePackable...) -> Subspace {
            return self.subspace(input)
        }
        
        public subscript(index: FDBTuplePackable...) -> Subspace {
            return self.subspace(index)
        }
    }
}

extension FDB.Subspace: AnyFDBKey {
    public func asFDBKey() -> Bytes {
        return self.prefix
    }
}
