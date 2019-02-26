public extension FDB {
    public struct KeyValue {
        public let key: Bytes
        public let value: Bytes
    }
    
    public typealias KeyValues = [KeyValue]
    
    public struct KeyValuesResult {
        public let records: [FDB.KeyValue]
        public let hasMore: Bool
    }
}

extension FDB.KeyValue: Equatable {
    public static func == (lhs: FDB.KeyValue, rhs: FDB.KeyValue) -> Bool {
        return lhs.key == rhs.key && lhs.value == rhs.value
    }
}

extension FDB.KeyValuesResult: Equatable {
    public static func == (lhs: FDB.KeyValuesResult, rhs: FDB.KeyValuesResult) -> Bool {
        return lhs.records == rhs.records && lhs.hasMore == rhs.hasMore
    }
}
