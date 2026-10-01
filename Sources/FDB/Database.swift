import CFDB
import Logging

extension FDB {
    /// A connection to a FoundationDB cluster.
    ///
    /// Database is thread-safe and is meant to be long-lived and shared: create it once and pass it around.
    /// Any number of databases (including ones pointing to different clusters) can be opened within a process.
    ///
    /// The network (see ``FDB/Network``) is started automatically on first database creation.
    public final class Database: Sendable {
        /// Default transaction retry limit, see ``init(clusterFile:transactionRetryLimit:transactionTimeout:logger:)``
        public static let defaultTransactionRetryLimit: Int64 = 100

        nonisolated(unsafe) let pointer: OpaquePointer
        let logger: Logger

        /// Opens a database.
        ///
        /// Note that this doesn't connect to the cluster yet: connection is established lazily, and connectivity
        /// problems surface as errors (or timeouts) of the first transactions.
        ///
        /// - parameters:
        ///   - clusterFile: Path to the cluster file. `nil` means the default one (`FDB_CLUSTER_FILE` environment
        ///     variable, `fdb.cluster` in the current directory or the platform default location).
        ///   - transactionRetryLimit: Default retry limit for transactions created by this database
        ///     (see ``FDB/DatabaseOption/transactionRetryLimit(_:)``). Without a limit, FoundationDB retries
        ///     retryable errors (like conflicts) indefinitely. `nil` means no limit.
        ///   - transactionTimeout: Default timeout for transactions created by this database. `nil` means no timeout.
        ///   - logger: Logger for debug output
        public init(
            clusterFile: String? = nil,
            transactionRetryLimit: Int64? = Database.defaultTransactionRetryLimit,
            transactionTimeout: Duration? = nil,
            logger: Logger = Logger(label: "FDB")
        ) throws(FDB.Error) {
            try Network.start()

            var pointer: OpaquePointer?
            try fdb_create_database(clusterFile, &pointer).check()
            self.pointer = pointer!
            self.logger = logger

            try self.configure(transactionRetryLimit: transactionRetryLimit, transactionTimeout: transactionTimeout)
        }

        /// Opens a database using a connection string (the contents of a cluster file) instead of a cluster file
        public init(
            connectionString: String,
            transactionRetryLimit: Int64? = Database.defaultTransactionRetryLimit,
            transactionTimeout: Duration? = nil,
            logger: Logger = Logger(label: "FDB")
        ) throws(FDB.Error) {
            try Network.start()

            var pointer: OpaquePointer?
            try fdb_create_database_from_connection_string(connectionString, &pointer).check()
            self.pointer = pointer!
            self.logger = logger

            try self.configure(transactionRetryLimit: transactionRetryLimit, transactionTimeout: transactionTimeout)
        }

        deinit {
            fdb_database_destroy(self.pointer)
        }

        private func configure(transactionRetryLimit: Int64?, transactionTimeout: Duration?) throws(FDB.Error) {
            if let transactionRetryLimit {
                try self.setOption(.transactionRetryLimit(transactionRetryLimit))
            }
            if let transactionTimeout {
                let (seconds, attoseconds) = transactionTimeout.components
                try self.setOption(.transactionTimeout(milliseconds: seconds * 1000 + attoseconds / 1_000_000_000_000_000))
            }
        }

        /// Sets a database option
        public func setOption(_ option: DatabaseOption) throws(FDB.Error) {
            try option.withValue { (value) throws(FDB.Error) in
                try fdb_database_set_option(self.pointer, option.code, value.baseAddress, Int32(value.count)).check()
            }
        }

        /// Creates a new transaction.
        ///
        /// Prefer ``withTransaction(_:)``, which handles commit and retries.
        public func makeTransaction() throws(FDB.Error) -> Transaction {
            var pointer: OpaquePointer?
            try fdb_database_create_transaction(self.pointer, &pointer).check()
            return Transaction(pointer!, database: self)
        }
    }
}
