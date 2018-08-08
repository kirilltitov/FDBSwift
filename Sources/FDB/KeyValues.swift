public struct KeyValue {
    public let key: Bytes
    public let value: Bytes
}

public struct KeyValuesResult {
    public let records: [KeyValue]
    public let hasMore: Bool
}

extension KeyValue: Equatable {
    public static func == (lhs: KeyValue, rhs: KeyValue) -> Bool {
        return lhs.key == rhs.key && lhs.value == rhs.value
    }
}

extension KeyValuesResult: Equatable {
    public static func == (lhs: KeyValuesResult, rhs: KeyValuesResult) -> Bool {
        return lhs.records == rhs.records && lhs.hasMore == rhs.hasMore
    }
}
