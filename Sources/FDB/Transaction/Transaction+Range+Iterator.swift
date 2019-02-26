import CFDB

public extension FDB.Transaction {
    /// A wrapper for range get with inner state (iteration) for simple iterating over large key ranges
    public struct RangeIterator {
        public let transaction: FDB.Transaction
        public let range: FDB.RangeKey
        public let beginEqual: Bool
        public let beginOffset: Int32
        public let endEqual: Bool
        public let endOffset: Int32
        public let limit: Int32
        public let targetBytes: Int32
        public let snapshot: Int32
        public let reverse: Bool
        public private(set) var iteration: Int32 = 1
        public private(set) var hasMore: Bool = true

        public init(
            transaction: FDB.Transaction,
            range: FDB.RangeKey,
            beginEqual: Bool = false,
            beginOffset: Int32 = 1,
            endEqual: Bool = false,
            endOffset: Int32 = 1,
            limit: Int32 = 0,
            targetBytes: Int32 = 0,
            snapshot: Int32 = 0,
            reverse: Bool = false
        ) {
            self.transaction = transaction
            self.range = range
            self.beginEqual = beginEqual
            self.beginOffset = beginOffset
            self.endEqual = endEqual
            self.endOffset = endOffset
            self.limit = limit
            self.targetBytes = targetBytes
            self.snapshot = snapshot
            self.reverse = reverse
        }

        /// Returns next bulk of records from FoundationDB if present, else nil
        ///
        /// - Returns: A non-empty array of `KeyValue`s or `nil` if no records returned from DB
        public mutating func next() throws -> FDB.KeyValues? {
            guard self.hasMore else {
                return nil
            }

            let result: FDB.KeyValuesResult = try self.transaction.get(
                range: self.range,
                beginEqual: self.beginEqual,
                beginOffset: self.beginOffset,
                endEqual: self.endEqual,
                endOffset: self.endOffset,
                limit: self.limit,
                targetBytes: self.targetBytes,
                mode: .iterator,
                iteration: self.iteration,
                snapshot: self.snapshot,
                reverse: self.reverse,
                commit: false
            )
            
            print(result.records.map { $0.value })
            
            guard result.records.count > 0 else {
                self.hasMore = false
                return nil
            }

            self.iteration += 1
            self.hasMore = result.hasMore

            return result.records
        }
    }
}

public extension FDB.Transaction {
    /// Creates and returns an iterator for range get
    ///
    /// - Returns: Iterator struct
    public func get(
        range: FDB.RangeKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        snapshot: Int32 = 0,
        reverse: Bool = false
    ) -> RangeIterator {
        return FDB.Transaction.RangeIterator(
            transaction: self,
            range: range,
            beginEqual: beginEqual,
            beginOffset: beginOffset,
            endEqual: endEqual,
            endOffset: endOffset,
            limit: limit,
            targetBytes: targetBytes,
            snapshot: snapshot,
            reverse: reverse
        )
    }
}
