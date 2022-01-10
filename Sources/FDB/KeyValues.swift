public extension FDB {
    /// A holder for key-value pair
    struct KeyValue {
        public let key: Bytes
        public let value: Bytes
    }

    /// A holder for key-value pairs result returned from range get
    struct KeyValuesResult {
        /// Records returned from range get
        public let records: [FDB.KeyValue]

        /// Indicates whether there are more results in FDB
        public let hasMore: Bool
    }
}

extension FDB.KeyValue: Equatable {
    public static func == (lhs: FDB.KeyValue, rhs: FDB.KeyValue) -> Bool {
        lhs.key == rhs.key && lhs.value == rhs.value
    }
}

extension FDB.KeyValuesResult: Equatable {
    public static func == (lhs: FDB.KeyValuesResult, rhs: FDB.KeyValuesResult) -> Bool {
        lhs.records == rhs.records && lhs.hasMore == rhs.hasMore
    }
}
