extension FDB {
    /// A key prefix, usually a packed tuple, used to group related keys:
    ///
    /// ```swift
    /// let users = FDB.Subspace("app", "users")
    /// tr.set(key: users[userID, "email"], value: ...)
    /// let all = try await tr.getAll(users.range)
    /// ```
    public struct Subspace: Hashable, Sendable, FDB.Key {
        /// Raw prefix of all keys in this subspace
        public let prefix: Bytes

        private let versionstampOffset: Int?
        private let versionstampCount: Int

        /// Creates a subspace with given raw prefix
        public init(prefix: Bytes) {
            self.prefix = prefix
            self.versionstampOffset = nil
            self.versionstampCount = 0
        }

        /// Creates a subspace with a prefix from given tuple
        public init(_ tuple: Tuple) {
            self.prefix = tuple.packed
            self.versionstampOffset = tuple.versionstampOffset
            self.versionstampCount = tuple.versionstampCount
        }

        /// Creates a subspace with a prefix from given tuple elements
        public init<each T: FDB.TuplePackable>(_ element: repeat each T) {
            self.init(Tuple(repeat each element))
        }

        private init(prefix: Bytes, appending tuple: Tuple, base: Subspace) {
            self.prefix = prefix + tuple.packed
            self.versionstampOffset = base.versionstampOffset
                ?? tuple.versionstampOffset.map { $0 + prefix.count }
            self.versionstampCount = base.versionstampCount + tuple.versionstampCount
        }

        /// Returns a nested subspace with given tuple elements appended to the prefix
        public subscript<each T: FDB.TuplePackable>(_ element: repeat each T) -> Subspace {
            Subspace(prefix: self.prefix, appending: Tuple(repeat each element), base: self)
        }

        /// Returns a nested subspace with given tuple appended to the prefix
        public func subspace(_ tuple: Tuple) -> Subspace {
            Subspace(prefix: self.prefix, appending: tuple, base: self)
        }

        /// Range of all tuple-encoded keys in this subspace (the prefix itself is not included)
        public var range: KeyRange {
            KeyRange(begin: self.prefix + [0x00], end: self.prefix + [0xFF])
        }

        /// Whether given key belongs to this subspace
        public func contains(_ key: some FDB.Key) -> Bool {
            key.fdbKey.starts(with: self.prefix)
        }

        /// Decodes the tuple following the prefix of this subspace in given key
        public func unpack(_ key: some FDB.Key) throws(FDB.Error) -> Tuple {
            let key = key.fdbKey
            guard key.starts(with: self.prefix) else {
                throw .unpackInvalidInput
            }
            return try Tuple(packed: Bytes(key[self.prefix.count...]))
        }

        // MARK: FDB.Key

        public var fdbKey: Bytes {
            self.prefix
        }

        public func incompleteVersionstampOffset() throws(FDB.Error) -> Int? {
            guard self.versionstampCount <= 1 else {
                throw .multipleIncompleteVersionstamps
            }
            return self.versionstampOffset
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.prefix == rhs.prefix
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.prefix)
        }
    }
}
