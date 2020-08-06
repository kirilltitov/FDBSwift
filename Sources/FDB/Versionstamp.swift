public extension FDB {
    
    /// Versionstamp type, as implemented by the Python, Java, and Go bindings
    struct Versionstamp: Equatable {
        /// 8-bytes: A big-endian, unsigned version corresponding to the commit version of a transaction, immutable.
        public let transactionCommitVersion: UInt64
        /// 2-bytes: A big-endian, unsigned batch number ordering transactions that are committed at the same version, immutable.
        public let batchNumber: UInt16
        /// Optional 2-byes: Extra ordering information to order writes within a single transaction, thereby providing a global order for all versions.
        public var userData: UInt16?
        
        /// Initializes a Versionstamp with the specified transaction commit version, batch number, and optional user data. If the user data is specified, a 96-bit versionstamp will be encoded, otherwise an 80-bit verstion stamp without the user data will be encoded.
        /// - Parameters:
        ///   - transactionCommitVersion: A big-endian, unsigned version corresponding to the commit version of a transaction.
        ///   - batchNumber: A big-endian, unsigned batch number ordering transactions that are committed at the same version.
        ///   - userData: Extra ordering information to order writes within a single transaction, thereby providing a global order for all versions.
        public init(transactionCommitVersion: UInt64, batchNumber: UInt16, userData: UInt16? = nil) {
            self.transactionCommitVersion = transactionCommitVersion
            self.batchNumber = batchNumber
            self.userData = userData
        }
        
        /// Initializes a new incomplete Versionstamp suitable for passing to an atomic operation with the .setVersionstampedKey option. If the user data is specified, a 96-bit versionstamp will be encoded, otherwise an 80-bit verstion stamp without the user data will be encoded.
        /// - Parameter userData: Extra ordering information to order writes within a single transaction, thereby providing a global order for all versions.
        public init(userData: UInt16? = nil) {
            self.init(transactionCommitVersion: 0, batchNumber: 0, userData: userData)
        }
    }
}

extension FDB.Versionstamp: FDBTuplePackable {
    public func pack() -> Bytes {
        var result = Bytes()
        if userData == nil {
            result.append(FDB.Tuple.Prefix.VERSIONSTAMP_80BIT)
        } else {
            result.append(FDB.Tuple.Prefix.VERSIONSTAMP_96BIT)
        }
        
        result.append(contentsOf: getBytes(transactionCommitVersion.bigEndian))
        result.append(contentsOf: getBytes(batchNumber.bigEndian))
        
        if let userData = userData {
            result.append(contentsOf: getBytes(userData.bigEndian))
        }
        
        return result
    }
}
