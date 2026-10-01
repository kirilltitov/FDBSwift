extension FDB {
    /// A versionstamp: a 10-byte, unique, monotonically (but not sequentially) increasing value assigned to each
    /// committed transaction, plus an optional 2-byte user version for ordering within a transaction.
    ///
    /// An incomplete versionstamp (see ``init(userVersion:)``) is a placeholder which is filled in by the cluster
    /// on commit, see ``FDB/Transaction/set(versionstampedKey:value:)``.
    public struct Versionstamp: Hashable, Sendable {
        /// Commit version of the transaction
        public let transactionCommitVersion: UInt64

        /// Order of the transaction within its commit batch
        public let batchNumber: UInt16

        /// Optional user version. Versionstamps with user version are encoded as 96-bit versionstamps in tuples.
        public var userVersion: UInt16?

        public init(transactionCommitVersion: UInt64, batchNumber: UInt16, userVersion: UInt16? = nil) {
            self.transactionCommitVersion = transactionCommitVersion
            self.batchNumber = batchNumber
            self.userVersion = userVersion
        }

        /// An incomplete versionstamp to be filled in by the cluster on commit
        public init(userVersion: UInt16? = nil) {
            self.init(transactionCommitVersion: .max, batchNumber: .max, userVersion: userVersion)
        }

        /// Reads a 10-byte (big-endian) versionstamp
        init(bytes: UnsafeRawBufferPointer) {
            self.init(
                transactionCommitVersion: UInt64(bigEndian: bytes.loadUnaligned(as: UInt64.self)),
                batchNumber: UInt16(bigEndian: bytes.loadUnaligned(fromByteOffset: 8, as: UInt16.self))
            )
        }

        /// Whether this versionstamp is complete, i.e. not a placeholder
        public var isComplete: Bool {
            self.transactionCommitVersion != .max || self.batchNumber != .max
        }

        /// Returns a copy of this versionstamp with given user version
        public func with(userVersion: UInt16?) -> Self {
            var copy = self
            copy.userVersion = userVersion
            return copy
        }
    }
}
