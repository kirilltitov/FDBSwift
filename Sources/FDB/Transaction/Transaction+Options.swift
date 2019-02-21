import CFDB

public extension FDB.Transaction {
    public enum Option: UInt32 {
        case causalWriteRisky                  = 10  // FDB_TR_OPTION_CAUSAL_WRITE_RISKY
        case causalReadRisky                   = 20  // FDB_TR_OPTION_CAUSAL_READ_RISKY
        case causalReadDisable                 = 21  // FDB_TR_OPTION_CAUSAL_READ_DISABLE
        case nextWriteNoWriteConflictRange     = 30  // FDB_TR_OPTION_NEXT_WRITE_NO_WRITE_CONFLICT_RANGE
        case readYourWritesDisable             = 51  // FDB_TR_OPTION_READ_YOUR_WRITES_DISABLE
        case durabilityDatacenter              = 110 // FDB_TR_OPTION_DURABILITY_DATACENTER
        case durabilityRisky                   = 120 // FDB_TR_OPTION_DURABILITY_RISKY
        case prioritySystemImmediate           = 200 // FDB_TR_OPTION_PRIORITY_SYSTEM_IMMEDIATE
        case priorityBatch                     = 201 // FDB_TR_OPTION_PRIORITY_BATCH
        case initializeNewDatabase             = 300 // FDB_TR_OPTION_INITIALIZE_NEW_DATABASE
        case accessSystemKeys                  = 301 // FDB_TR_OPTION_ACCESS_SYSTEM_KEYS
        case readSystemKeys                    = 302 // FDB_TR_OPTION_READ_SYSTEM_KEYS
        case debugRetryLogging                 = 401 // FDB_TR_OPTION_DEBUG_RETRY_LOGGING
        case transactionLoggingEnable          = 402 // FDB_TR_OPTION_TRANSACTION_LOGGING_ENABLE
        case timeout                           = 500 // FDB_TR_OPTION_TIMEOUT
        case retryLimit                        = 501 // FDB_TR_OPTION_RETRY_LIMIT
        case maxRetryDelay                     = 502 // FDB_TR_OPTION_MAX_RETRY_DELAY
        case snapshotRywEnable                 = 600 // FDB_TR_OPTION_SNAPSHOT_RYW_ENABLE
        case snapshotRywDisable                = 601 // FDB_TR_OPTION_SNAPSHOT_RYW_DISABLE
        case lockAware                         = 700 // FDB_TR_OPTION_LOCK_AWARE
        case usedDuringCommitProtectionDisable = 701 // FDB_TR_OPTION_USED_DURING_COMMIT_PROTECTION_DISABLE
        case readLockAware                     = 70  // FDB_TR_OPTION_READ_LOCK_AWARE

        // deprecated
        case readAheadDisable            = 52  // FDB_TR_OPTION_READ_AHEAD_DISABLE
        case durabilityDevNullIsWebScale = 130 // FDB_TR_OPTION_DURABILITY_DEV_NULL_IS_WEB_SCALE
    }
    
    internal func setOption(
        _ option: FDB.Transaction.Option,
        param: UnsafePointer<Byte>? = nil,
        paramLength: Int32 = 0
    ) throws -> FDB.Transaction {
        try fdb_transaction_set_option(
            self.pointer,
            FDBTransactionOption(option.rawValue),
            param,
            paramLength
        ).orThrow()
        return self
    }
    
    public func setOption(
        _ option: FDB.Transaction.Option,
        param bytes: Bytes
    ) throws -> FDB.Transaction {
        return try self.setOption(
            option,
            param: UnsafePointer<UInt8>(bytes),
            paramLength: Int32(bytes.count)
        )
    }
    
    public func setOption(_ option: FDB.Transaction.Option, param string: String) throws -> FDB.Transaction {
        return try self.setOption(option, param: string.bytes)
    }
    
    public func setOption(_ option: FDB.Transaction.Option, param int: Int64) throws -> FDB.Transaction {
        return try self.setOption(option, param: getBytes(int))
    }

    public func setDebugRetryLogging(transactionName: String) throws -> FDB.Transaction {
        return try self.setOption(.debugRetryLogging, param: transactionName)
    }
    
    public func enableLogging(identifier: String) throws -> FDB.Transaction {
        return try self.setOption(.transactionLoggingEnable, param: identifier)
    }
    
    public func setTimeout(_ timeout: Int64) throws -> FDB.Transaction {
        return try self.setOption(.timeout, param: timeout)
    }
    
    public func setRetryLimit(_ retries: Int64) throws -> FDB.Transaction {
        return try self.setOption(.retryLimit, param: retries)
    }
    
    public func setMaxRetryDelay(_ delay: Int64) throws -> FDB.Transaction {
        return try self.setOption(.maxRetryDelay, param: delay)
    }
}
