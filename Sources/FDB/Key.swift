/// A type which can be used as a FoundationDB key
public protocol FDBKey: Sendable {
    /// Raw key bytes
    var fdbKey: Bytes { get }

    /// Position of the first incomplete versionstamp within ``fdbKey`` (if any),
    /// used by ``FDB/Transaction/set(versionstampedKey:value:)``.
    ///
    /// Throws if the key contains more than one incomplete versionstamp.
    func incompleteVersionstampOffset() throws(FDB.Error) -> Int?
}

public extension FDBKey {
    func incompleteVersionstampOffset() throws(FDB.Error) -> Int? {
        nil
    }
}

extension Array: FDBKey where Element == UInt8 {
    public var fdbKey: Bytes {
        self
    }
}

extension String: FDBKey {
    public var fdbKey: Bytes {
        Bytes(self.utf8)
    }
}

extension StaticString: FDBKey {
    public var fdbKey: Bytes {
        self.withUTF8Buffer { Bytes($0) }
    }
}

extension FDB {
    /// A half-open key range: `begin` is inclusive, `end` is exclusive
    public struct KeyRange: Hashable, Sendable {
        public let begin: Bytes
        public let end: Bytes

        public init(begin: some FDBKey, end: some FDBKey) {
            self.begin = begin.fdbKey
            self.end = end.fdbKey
        }

        /// All keys starting with given prefix
        ///
        /// Note: for tuple-encoded keys use ``FDB/Subspace/range`` instead.
        ///
        /// - precondition: prefix must contain at least one byte other than `0xFF`
        public init(prefix: some FDBKey) {
            let prefix = prefix.fdbKey
            self.begin = prefix
            self.end = Self.strinc(prefix)
        }

        /// Returns the first key which is greater than all keys starting with given prefix
        static func strinc(_ key: Bytes) -> Bytes {
            var key = key
            while let last = key.last, last == 0xFF {
                key.removeLast()
            }
            precondition(!key.isEmpty, "Key prefix must contain at least one byte other than 0xFF")
            key[key.count - 1] += 1
            return key
        }
    }

    /// Identifies a particular key in the database relative to another key, see
    /// [key selectors](https://apple.github.io/foundationdb/developer-guide.html#key-selectors)
    public struct KeySelector: Hashable, Sendable {
        public let key: Bytes
        public let orEqual: Bool
        public let offset: Int32

        public init(key: some FDBKey, orEqual: Bool, offset: Int32) {
            self.key = key.fdbKey
            self.orEqual = orEqual
            self.offset = offset
        }

        /// The last key less than given one
        public static func lastLessThan(_ key: some FDBKey) -> Self {
            Self(key: key, orEqual: false, offset: 0)
        }

        /// The last key less than or equal to given one
        public static func lastLessOrEqual(_ key: some FDBKey) -> Self {
            Self(key: key, orEqual: true, offset: 0)
        }

        /// The first key greater than given one
        public static func firstGreaterThan(_ key: some FDBKey) -> Self {
            Self(key: key, orEqual: true, offset: 1)
        }

        /// The first key greater than or equal to given one
        public static func firstGreaterOrEqual(_ key: some FDBKey) -> Self {
            Self(key: key, orEqual: false, offset: 1)
        }
    }

    /// A key-value pair
    public struct KeyValue: Hashable, Sendable {
        public let key: Bytes
        public let value: Bytes

        public init(key: Bytes, value: Bytes) {
            self.key = key
            self.value = value
        }
    }

    /// Result of a single range read
    public struct RangeResult: Hashable, Sendable {
        /// Key-value pairs in this batch
        public let records: [KeyValue]

        /// Whether there are more key-value pairs in the requested range
        public let hasMore: Bool
    }

    /// How range reads are transferred from the cluster
    public enum StreamingMode: Int32, Sendable {
        /// Client intends to consume the entire range and would like it all transferred as early as possible
        case wantAll = -2
        /// The default. The client doesn't know how much of the range it is likely to use and wants different
        /// performance concerns to be balanced.
        case iterator = -1
        /// The client has passed a specific row limit and wants that many rows delivered in a single batch
        case exact = 0
        /// Transfer data in batches small enough to not be much more expensive than reading individual rows
        case small = 1
        /// Transfer data in batches sized in between small and large
        case medium = 2
        /// Transfer data in batches large enough to be, in a high-concurrency environment, nearly as efficient as possible
        case large = 3
        /// Transfer data in batches large enough that an individual client can get reasonable read bandwidth
        case serial = 4
    }

    /// Atomic mutation type, see ``FDB/Transaction/atomic(_:key:value:)``
    public enum MutationType: UInt32, Sendable {
        /// Addition of little-endian integers
        case add = 2
        /// Bitwise `and`
        case bitAnd = 6
        /// Bitwise `or`
        case bitOr = 7
        /// Bitwise `xor`
        case bitXor = 8
        /// Appends value to the end of the existing value, if the result fits into the value size limit
        case appendIfFits = 9
        /// Little-endian integer maximum
        case max = 12
        /// Little-endian integer minimum
        case min = 13
        /// Sets a key with a versionstamp, see ``FDB/Transaction/set(versionstampedKey:value:)``
        case setVersionstampedKey = 14
        /// Sets a value with a versionstamp
        case setVersionstampedValue = 15
        /// Lexicographic minimum of byte strings
        case byteMin = 16
        /// Lexicographic maximum of byte strings
        case byteMax = 17
        /// Clears the key if its value equals to the given one
        case compareAndClear = 20
    }
}
