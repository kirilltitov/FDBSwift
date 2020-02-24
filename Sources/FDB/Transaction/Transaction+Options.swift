import CFDB

public extension FDB.Transaction {
    enum Option {
        /// The transaction, if not self-conflicting, may be committed a second time after commit succeeds,
        /// in the event of a fault
        case causalWriteRisky

        /// The read version will be committed, and usually will be the latest committed,
        /// but might not be the latest committed in the event of a fault or partition
        case causalReadRisky

        case causalReadDisable

        /// The next write performed on this transaction will not generate a write conflict range.
        /// As a result, other transactions which read the key(s) being modified by the next write
        /// will not conflict with this transaction. Care needs to be taken when using this option
        /// on a transaction that is shared between multiple threads. When setting this option,
        /// write conflict ranges will be disabled on the next write operation, regardless of what thread it is on.
        case nextWriteNoWriteConflictRange

        /// Reads performed by a transaction will not see any prior mutations that occured in that transaction,
        /// instead seeing the value which was in the database at the transaction's read version.
        /// This option may provide a small performance benefit for the client, but also disables a number
        /// of client-side optimizations which are beneficial for transactions which tend to read and write
        /// the same keys within a single transaction.
        case readYourWritesDisable

        case durabilityDatacenter

        case durabilityRisky

        /// Specifies that this transaction should be treated as highest priority and that lower priority
        /// transactions should block behind this one. Use is discouraged outside of low-level tools
        case prioritySystemImmediate

        /// Specifies that this transaction should be treated as low priority and that default priority transactions
        /// should be processed first. Useful for doing batch work simultaneously with latency-sensitive work
        case priorityBatch

        /// This is a write-only transaction which sets the initial configuration.
        /// This option is designed for use by database system tools only.
        case initializeNewDatabase

        /// Allows this transaction to read and modify system keys (those that start with the byte 0xFF)
        case accessSystemKeys

        /// Allows this transaction to read system keys (those that start with the byte 0xFF)
        case readSystemKeys

        /// Snapshot read operations will see the results of writes done in the same transaction.
        case snapshotRywEnable

        /// Snapshot read operations will not see the results of writes done in the same transaction.
        case snapshotRywDisable

        /// The transaction can read and write to locked databases,
        /// and is resposible for checking that it took the lock.
        case lockAware

        /// By default, operations that are performed on a transaction while it is being committed will not only
        /// fail themselves, but they will attempt to fail other in-flight operations (such as the commit) as well.
        /// This behavior is intended to help developers discover situations where operations could be
        /// unintentionally executed after the transaction has been reset. Setting this option removes that protection,
        /// causing only the offending operation to fail.
        case usedDuringCommitProtectionDisable

        /// The transaction can read from locked databases.
        case readLockAware

        case debugRetryLogging(transactionName: String)

        /// Enables tracing for this transaction and logs results to the client trace logs.
        /// Client trace logging must be enabled to get log output.
        case transactionLoggingEnable(identifier: String)

        /// Set a timeout in milliseconds which, when elapsed, will cause the transaction automatically to be cancelled.
        /// Valid parameter values are ``[0, INT_MAX]``. If set to 0, will disable all timeouts.
        /// All pending and any future uses of the transaction will throw an exception.
        /// The transaction can be used again after it is reset. Like all transaction options,
        /// a timeout must be reset after a call to onError. This behavior allows the user to make the timeout dynamic.
        case timeout(milliseconds: Int64)

        /// Set a maximum number of retries after which additional calls to onError will throw the most recently
        /// seen error code. Valid parameter values are ``[-1, INT_MAX]``. If set to -1, will disable the retry limit.
        /// Like all transaction options, the retry limit must be reset after a call to onError.
        /// This behavior allows the user to make the retry limit dynamic.
        case retryLimit(retries: Int64)

        /// Set the maximum amount of backoff delay incurred in the call to onError if the error is retryable.
        /// Defaults to 1000 ms. Valid parameter values are ``[0, INT_MAX]``. Like all transaction options,
        /// the maximum retry delay must be reset after a call to onError. If the maximum retry delay is less
        /// than the current retry delay of the transaction, then the current retry delay will be
        /// clamped to the maximum retry delay.
        case maxRetryDelay(milliseconds: Int64)

        @usableFromInline
        internal func setOption(transaction: FDB.Transaction) throws {
            let internalOption: FDBTransactionOption
            var value = Bytes([])

            switch self {
            case .causalWriteRisky:
                internalOption = FDB_TR_OPTION_CAUSAL_WRITE_RISKY
            case .causalReadRisky:
                internalOption = FDB_TR_OPTION_CAUSAL_READ_RISKY
            case .causalReadDisable:
                internalOption = FDB_TR_OPTION_CAUSAL_READ_DISABLE
            case .nextWriteNoWriteConflictRange:
                internalOption = FDB_TR_OPTION_NEXT_WRITE_NO_WRITE_CONFLICT_RANGE
            case .readYourWritesDisable:
                internalOption = FDB_TR_OPTION_READ_YOUR_WRITES_DISABLE
            case .durabilityDatacenter:
                internalOption = FDB_TR_OPTION_DURABILITY_DATACENTER
            case .durabilityRisky:
                internalOption = FDB_TR_OPTION_DURABILITY_RISKY
            case .prioritySystemImmediate:
                internalOption = FDB_TR_OPTION_PRIORITY_SYSTEM_IMMEDIATE
            case .priorityBatch:
                internalOption = FDB_TR_OPTION_PRIORITY_BATCH
            case .initializeNewDatabase:
                internalOption = FDB_TR_OPTION_INITIALIZE_NEW_DATABASE
            case .accessSystemKeys:
                internalOption = FDB_TR_OPTION_ACCESS_SYSTEM_KEYS
            case .readSystemKeys:
                internalOption = FDB_TR_OPTION_READ_SYSTEM_KEYS
            case .snapshotRywEnable:
                internalOption = FDB_TR_OPTION_SNAPSHOT_RYW_ENABLE
            case .snapshotRywDisable:
                internalOption = FDB_TR_OPTION_SNAPSHOT_RYW_DISABLE
            case .lockAware:
                internalOption = FDB_TR_OPTION_LOCK_AWARE
            case .usedDuringCommitProtectionDisable:
                internalOption = FDB_TR_OPTION_USED_DURING_COMMIT_PROTECTION_DISABLE
            case .readLockAware:
                internalOption = FDB_TR_OPTION_READ_LOCK_AWARE
            case let .debugRetryLogging(transactionName):
                internalOption = FDB_TR_OPTION_DEBUG_RETRY_LOGGING
                value = transactionName.bytes
            case let .transactionLoggingEnable(identifier):
                internalOption = FDB_TR_OPTION_TRANSACTION_LOGGING_ENABLE
                value = identifier.bytes
            case let .timeout(milliseconds):
                internalOption = FDB_TR_OPTION_TIMEOUT
                value = getBytes(milliseconds)
            case let .retryLimit(retries):
                internalOption = FDB_TR_OPTION_RETRY_LIMIT
                value = getBytes(retries)
            case let .maxRetryDelay(milliseconds):
                internalOption = FDB_TR_OPTION_MAX_RETRY_DELAY
                value = getBytes(milliseconds)
            }

            try fdb_transaction_set_option(
                transaction.pointer,
                internalOption,
                value,
                value.length
            ).orThrow()
        }
    }

    /// Sets a transaction option to current transaction
    ///
    /// - parameters:
    ///   - option: Transaction option
    /// - returns: current transaction (`self`)
    func setOption(_ option: FDB.Transaction.Option) throws -> AnyFDBTransaction {
        try option.setOption(transaction: self)

        return self
    }
}
