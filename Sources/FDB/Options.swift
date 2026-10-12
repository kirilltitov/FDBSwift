import CFDB

/// Raw option parameter as expected by FoundationDB C API
@usableFromInline
enum OptionValue: Sendable {
    case none
    case int(Int64)
    case bytes(Bytes)

    static func string(_ string: String) -> Self {
        .bytes(Bytes(string.utf8))
    }

    func withUnsafeBytes<R, E: Error>(_ body: (UnsafeBufferPointer<UInt8>) throws(E) -> R) throws(E) -> R {
        switch self {
        case .none:
            return try body(UnsafeBufferPointer(start: nil, count: 0))
        case let .int(value):
            // Integer options are passed as 64-bit little-endian
            var littleEndian = value.littleEndian
            return try Swift.withUnsafeBytes(of: &littleEndian) { (raw) throws(E) -> R in
                try body(raw.assumingMemoryBound(to: UInt8.self))
            }
        case let .bytes(bytes):
            return try bytes.withUnsafeBufferPointer { (buffer) throws(E) -> R in try body(buffer) }
        }
    }
}

protocol FDBOption {
    associatedtype Code
    var code: Code { get }
    var value: OptionValue { get }
}

extension FDBOption {
    func withValue<R, E: Error>(_ body: (UnsafeBufferPointer<UInt8>) throws(E) -> R) throws(E) -> R {
        try self.value.withUnsafeBytes(body)
    }
}

// MARK: - Network options

extension FDB {
    /// Network option, see ``FDB/Network/setOption(_:)``
    public enum NetworkOption: Sendable, FDBOption {
        /// Enables trace output to a file in a directory of the clients choosing
        case traceEnable(directory: String)
        /// Sets the maximum size in bytes of a single trace output file
        case traceRollSize(bytes: Int64)
        /// Sets the maximum size of all the trace output files put together
        case traceMaxLogsSize(bytes: Int64)
        /// Sets the `LogGroup` attribute with the specified value for all events in the trace output files
        case traceLogGroup(String)
        /// Select the format of the log files: `xml` (the default) or `json`
        case traceFormat(String)
        /// Once provided, this string will be used to replace the port/PID in the log file names
        case traceFileIdentifier(String)
        /// Set internal tuning or debugging knobs
        case knob(name: String, value: String)
        /// Set the certificate chain
        case tlsCertBytes(Bytes)
        /// Set the file from which to load the certificate chain
        case tlsCertPath(String)
        /// Set the private key corresponding to your own certificate
        case tlsKeyBytes(Bytes)
        /// Set the file from which to load the private key corresponding to your own certificate
        case tlsKeyPath(String)
        /// Set the peer certificate field verification criteria
        case tlsVerifyPeers(String)
        /// Set the certificate authority bundle
        case tlsCABytes(Bytes)
        /// Set the file from which to load the certificate authority bundle
        case tlsCAPath(String)
        /// Set the passphrase for encrypted private key. Must be set before the key.
        case tlsPassword(String)
        /// Prevent client from connecting to a non-TLS endpoint by throwing on connect
        case tlsDisablePlaintextConnection
        /// Disables the multi-version client API and instead uses the local client directly
        case disableMultiVersionClientAPI
        /// Callbacks from external client libraries can be called from threads created by the FoundationDB client library
        case callbacksOnExternalThreads
        /// Adds an external client library for use by the multi-version client API
        case externalClientLibrary(path: String)
        /// Searches the specified path for dynamic libraries and adds them to the list of client libraries
        case externalClientDirectory(path: String)
        /// Prevents connections through the local client, allowing only connections through externally loaded clients
        case disableLocalClient
        /// Spawns multiple worker threads for each version of the client that is loaded
        case clientThreadsPerVersion(Int64)
        /// Retain temporary external client library copies that are created for enabling multi-threading
        case retainClientLibraryCopies
        /// Ignore the failure to initialize some of the external clients
        case ignoreExternalClientFailures
        /// Fail with an error if there is no client matching the server version the client is connecting to
        case failIncompatibleClient
        /// Disables logging of client statistics, such as sampled transaction activity
        case disableClientStatisticsLogging
        /// Enables debugging feature to perform run loop profiling. Requires trace logging to be enabled.
        case enableRunLoopProfiling
        /// Sets the directory for storing temporary files created by FDB client, such as temporary copies of client libraries
        case clientTmpDir(String)
        /// Enable BUGGIFY (testing only)
        case buggifyEnable
        /// Disable BUGGIFY (testing only)
        case buggifyDisable

        var code: FDBNetworkOption {
            switch self {
            case .traceEnable: FDB_NET_OPTION_TRACE_ENABLE
            case .traceRollSize: FDB_NET_OPTION_TRACE_ROLL_SIZE
            case .traceMaxLogsSize: FDB_NET_OPTION_TRACE_MAX_LOGS_SIZE
            case .traceLogGroup: FDB_NET_OPTION_TRACE_LOG_GROUP
            case .traceFormat: FDB_NET_OPTION_TRACE_FORMAT
            case .traceFileIdentifier: FDB_NET_OPTION_TRACE_FILE_IDENTIFIER
            case .knob: FDB_NET_OPTION_KNOB
            case .tlsCertBytes: FDB_NET_OPTION_TLS_CERT_BYTES
            case .tlsCertPath: FDB_NET_OPTION_TLS_CERT_PATH
            case .tlsKeyBytes: FDB_NET_OPTION_TLS_KEY_BYTES
            case .tlsKeyPath: FDB_NET_OPTION_TLS_KEY_PATH
            case .tlsVerifyPeers: FDB_NET_OPTION_TLS_VERIFY_PEERS
            case .tlsCABytes: FDB_NET_OPTION_TLS_CA_BYTES
            case .tlsCAPath: FDB_NET_OPTION_TLS_CA_PATH
            case .tlsPassword: FDB_NET_OPTION_TLS_PASSWORD
            case .tlsDisablePlaintextConnection: FDB_NET_OPTION_TLS_DISABLE_PLAINTEXT_CONNECTION
            case .disableMultiVersionClientAPI: FDB_NET_OPTION_DISABLE_MULTI_VERSION_CLIENT_API
            case .callbacksOnExternalThreads: FDB_NET_OPTION_CALLBACKS_ON_EXTERNAL_THREADS
            case .externalClientLibrary: FDB_NET_OPTION_EXTERNAL_CLIENT_LIBRARY
            case .externalClientDirectory: FDB_NET_OPTION_EXTERNAL_CLIENT_DIRECTORY
            case .disableLocalClient: FDB_NET_OPTION_DISABLE_LOCAL_CLIENT
            case .clientThreadsPerVersion: FDB_NET_OPTION_CLIENT_THREADS_PER_VERSION
            case .retainClientLibraryCopies: FDB_NET_OPTION_RETAIN_CLIENT_LIBRARY_COPIES
            case .ignoreExternalClientFailures: FDB_NET_OPTION_IGNORE_EXTERNAL_CLIENT_FAILURES
            case .failIncompatibleClient: FDB_NET_OPTION_FAIL_INCOMPATIBLE_CLIENT
            case .disableClientStatisticsLogging: FDB_NET_OPTION_DISABLE_CLIENT_STATISTICS_LOGGING
            case .enableRunLoopProfiling: FDB_NET_OPTION_ENABLE_RUN_LOOP_PROFILING
            case .clientTmpDir: FDB_NET_OPTION_CLIENT_TMP_DIR
            case .buggifyEnable: FDB_NET_OPTION_BUGGIFY_ENABLE
            case .buggifyDisable: FDB_NET_OPTION_BUGGIFY_DISABLE
            }
        }

        var value: OptionValue {
            switch self {
            case let .traceEnable(string), let .traceLogGroup(string), let .traceFormat(string),
                 let .traceFileIdentifier(string), let .tlsCertPath(string), let .tlsKeyPath(string),
                 let .tlsVerifyPeers(string), let .tlsCAPath(string), let .tlsPassword(string),
                 let .externalClientLibrary(string), let .externalClientDirectory(string), let .clientTmpDir(string):
                .string(string)
            case let .traceRollSize(int), let .traceMaxLogsSize(int), let .clientThreadsPerVersion(int):
                .int(int)
            case let .knob(name, value):
                .string("\(name)=\(value)")
            case let .tlsCertBytes(bytes), let .tlsKeyBytes(bytes), let .tlsCABytes(bytes):
                .bytes(bytes)
            case .tlsDisablePlaintextConnection, .disableMultiVersionClientAPI, .callbacksOnExternalThreads,
                 .disableLocalClient, .retainClientLibraryCopies, .ignoreExternalClientFailures,
                 .failIncompatibleClient, .disableClientStatisticsLogging, .enableRunLoopProfiling,
                 .buggifyEnable, .buggifyDisable:
                .none
            }
        }

        /// Description which is safe to put into logs: secrets are never included
        public var redactedDescription: String {
            switch self {
            case .tlsKeyBytes: "tlsKeyBytes(<private>)"
            case .tlsPassword: "tlsPassword(<private>)"
            case let .tlsCertBytes(bytes): "tlsCertBytes(<\(bytes.count) bytes>)"
            case let .tlsCABytes(bytes): "tlsCABytes(<\(bytes.count) bytes>)"
            default: "\(self)"
            }
        }
    }
}

// MARK: - Database options

extension FDB {
    /// Database option, see ``FDB/Database/setOption(_:)``
    public enum DatabaseOption: Sendable, FDBOption {
        /// Set the size of the client location cache
        case locationCacheSize(Int64)
        /// Set the maximum number of watches allowed to be outstanding on a database connection
        case maxWatches(Int64)
        /// Specify the machine ID of the client
        case machineID(String)
        /// Specify the datacenter ID of the client
        case datacenterID(String)
        /// Snapshot read operations will see the results of writes done in the same transaction (the default)
        case snapshotRYWEnable
        /// Snapshot read operations will not see the results of writes done in the same transaction
        case snapshotRYWDisable
        /// Default timeout (in milliseconds) for each transaction created by this database, 0 disables timeouts
        case transactionTimeout(milliseconds: Int64)
        /// Default maximum number of retries for each transaction created by this database, -1 disables the limit
        case transactionRetryLimit(Int64)
        /// Default maximum backoff delay (in milliseconds) incurred by retryable errors
        case transactionMaxRetryDelay(milliseconds: Int64)
        /// Default maximum transaction size in bytes
        case transactionSizeLimit(bytes: Int64)
        /// Automatically make commits idempotent (makes `commitUnknownResult` safe to retry)
        case transactionAutomaticIdempotency
        /// Report conflicting keys for each transaction
        case transactionReportConflictingKeys

        var code: FDBDatabaseOption {
            switch self {
            case .locationCacheSize: FDB_DB_OPTION_LOCATION_CACHE_SIZE
            case .maxWatches: FDB_DB_OPTION_MAX_WATCHES
            case .machineID: FDB_DB_OPTION_MACHINE_ID
            case .datacenterID: FDB_DB_OPTION_DATACENTER_ID
            case .snapshotRYWEnable: FDB_DB_OPTION_SNAPSHOT_RYW_ENABLE
            case .snapshotRYWDisable: FDB_DB_OPTION_SNAPSHOT_RYW_DISABLE
            case .transactionTimeout: FDB_DB_OPTION_TRANSACTION_TIMEOUT
            case .transactionRetryLimit: FDB_DB_OPTION_TRANSACTION_RETRY_LIMIT
            case .transactionMaxRetryDelay: FDB_DB_OPTION_TRANSACTION_MAX_RETRY_DELAY
            case .transactionSizeLimit: FDB_DB_OPTION_TRANSACTION_SIZE_LIMIT
            case .transactionAutomaticIdempotency: FDB_DB_OPTION_TRANSACTION_AUTOMATIC_IDEMPOTENCY
            case .transactionReportConflictingKeys: FDB_DB_OPTION_TRANSACTION_REPORT_CONFLICTING_KEYS
            }
        }

        var value: OptionValue {
            switch self {
            case let .locationCacheSize(int), let .maxWatches(int), let .transactionTimeout(int),
                 let .transactionRetryLimit(int), let .transactionMaxRetryDelay(int), let .transactionSizeLimit(int):
                .int(int)
            case let .machineID(string), let .datacenterID(string):
                .string(string)
            case .snapshotRYWEnable, .snapshotRYWDisable, .transactionAutomaticIdempotency,
                 .transactionReportConflictingKeys:
                .none
            }
        }
    }
}

// MARK: - Transaction options

extension FDB {
    /// Transaction option, see ``FDB/Transaction/setOption(_:)``
    public enum TransactionOption: Sendable, FDBOption {
        /// The transaction, if not self-conflicting, may be committed a second time after commit succeeds
        case causalWriteRisky
        /// The read version will be committed, and usually will be the latest committed, but might not be
        case causalReadRisky
        /// The next write performed on this transaction will not generate a write conflict range
        case nextWriteNoWriteConflictRange
        /// Reads performed by a transaction will not see any prior mutations that occurred in that transaction
        case readYourWritesDisable
        /// Specifies that this transaction should be treated as highest priority
        case prioritySystemImmediate
        /// Specifies that this transaction should be treated as low priority
        case priorityBatch
        /// Allows this transaction to read and modify system keys (those that start with the byte 0xFF)
        case accessSystemKeys
        /// Allows this transaction to read system keys (those that start with the byte 0xFF)
        case readSystemKeys
        /// Snapshot read operations will see the results of writes done in the same transaction
        case snapshotRYWEnable
        /// Snapshot read operations will not see the results of writes done in the same transaction
        case snapshotRYWDisable
        /// The transaction can read and write to locked databases
        case lockAware
        /// The transaction can read from locked databases
        case readLockAware
        /// Sets an identifier for client-side debug tracing of this transaction
        case debugTransactionIdentifier(String)
        /// Enables tracing for this transaction and logs results to the client trace logs
        case logTransaction
        /// Set a timeout in milliseconds which, when elapsed, will cause the transaction automatically to be cancelled
        case timeout(milliseconds: Int64)
        /// Set a maximum number of retries after which additional calls to `onError` will throw
        case retryLimit(Int64)
        /// Set the maximum amount of backoff delay incurred in the call to `onError` if the error is retryable
        case maxRetryDelay(milliseconds: Int64)
        /// Set the transaction size limit in bytes
        case sizeLimit(bytes: Int64)
        /// Automatically assign a random 16 byte idempotency id for this transaction
        case automaticIdempotency
        /// Adds a tag to the transaction that can be used to apply manual targeted throttling
        case tag(String)
        /// Adds a tag to the transaction that can be used to apply manual or automatic targeted throttling
        case autoThrottleTag(String)
        /// The transaction will report conflicting keys
        case reportConflictingKeys

        var code: FDBTransactionOption {
            switch self {
            case .causalWriteRisky: FDB_TR_OPTION_CAUSAL_WRITE_RISKY
            case .causalReadRisky: FDB_TR_OPTION_CAUSAL_READ_RISKY
            case .nextWriteNoWriteConflictRange: FDB_TR_OPTION_NEXT_WRITE_NO_WRITE_CONFLICT_RANGE
            case .readYourWritesDisable: FDB_TR_OPTION_READ_YOUR_WRITES_DISABLE
            case .prioritySystemImmediate: FDB_TR_OPTION_PRIORITY_SYSTEM_IMMEDIATE
            case .priorityBatch: FDB_TR_OPTION_PRIORITY_BATCH
            case .accessSystemKeys: FDB_TR_OPTION_ACCESS_SYSTEM_KEYS
            case .readSystemKeys: FDB_TR_OPTION_READ_SYSTEM_KEYS
            case .snapshotRYWEnable: FDB_TR_OPTION_SNAPSHOT_RYW_ENABLE
            case .snapshotRYWDisable: FDB_TR_OPTION_SNAPSHOT_RYW_DISABLE
            case .lockAware: FDB_TR_OPTION_LOCK_AWARE
            case .readLockAware: FDB_TR_OPTION_READ_LOCK_AWARE
            case .debugTransactionIdentifier: FDB_TR_OPTION_DEBUG_TRANSACTION_IDENTIFIER
            case .logTransaction: FDB_TR_OPTION_LOG_TRANSACTION
            case .timeout: FDB_TR_OPTION_TIMEOUT
            case .retryLimit: FDB_TR_OPTION_RETRY_LIMIT
            case .maxRetryDelay: FDB_TR_OPTION_MAX_RETRY_DELAY
            case .sizeLimit: FDB_TR_OPTION_SIZE_LIMIT
            case .automaticIdempotency: FDB_TR_OPTION_AUTOMATIC_IDEMPOTENCY
            case .tag: FDB_TR_OPTION_TAG
            case .autoThrottleTag: FDB_TR_OPTION_AUTO_THROTTLE_TAG
            case .reportConflictingKeys: FDB_TR_OPTION_REPORT_CONFLICTING_KEYS
            }
        }

        var value: OptionValue {
            switch self {
            case let .debugTransactionIdentifier(string), let .tag(string), let .autoThrottleTag(string):
                .string(string)
            case let .timeout(int), let .retryLimit(int), let .maxRetryDelay(int), let .sizeLimit(int):
                .int(int)
            case .causalWriteRisky, .causalReadRisky, .nextWriteNoWriteConflictRange, .readYourWritesDisable,
                 .prioritySystemImmediate, .priorityBatch, .accessSystemKeys, .readSystemKeys, .snapshotRYWEnable,
                 .snapshotRYWDisable, .lockAware, .readLockAware, .logTransaction, .automaticIdempotency,
                 .reportConflictingKeys:
                .none
            }
        }
    }
}
