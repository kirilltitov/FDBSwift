import CFDB
import Foundation
import NIO

public class FDB {
    internal typealias Cluster = OpaquePointer
    internal typealias Database = OpaquePointer

    private static let dbName: StaticString = "DB"

    internal static let dummyEventLoop = EmbeddedEventLoop()

    private let version: Int32 = FDB_API_VERSION
    private let networkStopTimeout: Int
    private let clusterFile: String
    private var cluster: FDB.Cluster?
    private var db: FDB.Database?

    private var isConnected = false

    public static var verbose = false

    private let semaphore = DispatchSemaphore(value: 0)

    /// Creates a new instance of FDB client with optional cluster file path and network stop timeout
    ///
    /// - parameters:
    ///   - clusterFile: path to `fdb.cluster` file. If not specified, default path (platform-specific) is chosen
    ///   - networkStopTimeout: timeout (in seconds) in which client should disconnect from FDB and stop all inner jobs
    public init(clusterFile: String? = nil, networkStopTimeout: Int = 10) {
        if let clusterFile = clusterFile {
            self.clusterFile = clusterFile
        } else {
            #if os(macOS)
                self.clusterFile = "/usr/local/etc/foundationdb/fdb.cluster"
            #else // assuming that else is linux
                self.clusterFile = "/etc/foundationdb/fdb.cluster"
            #endif
        }
        self.networkStopTimeout = networkStopTimeout

        self.debug("Using cluster file '\(self.clusterFile)'")
        self.debug("Network stop timeout is \(self.networkStopTimeout) seconds")

        self.selectAPIVersion()
    }

    deinit {
        self.debug("Deinit started")
        if self.isConnected {
            self.disconnect()
        }
    }

    /// Performs an explicit disconnect routine.
    public func disconnect() {
        if !self.isConnected {
            print("Trying to disconnect from FDB while not connected")
            return
        }
        fdb_stop_network().orDie()
        if self.semaphore.wait(for: self.networkStopTimeout) == .timedOut {
            print("Stop network timeout (\(self.networkStopTimeout) seconds)")
            exit(1)
        }
        self.debug("Network stopped")
        fdb_database_destroy(self.db)
        fdb_cluster_destroy(self.cluster)
        self.debug("Cluster and database destroyed")
        self.isConnected = false
    }

    /// Selects an API version
    ///
    /// Warning: API version must be less or equal to one that defined in `fdb_c.h` header file.
    ///
    /// Warning 2: must be called before any other call.
    private func selectAPIVersion() {
        fdb_select_api_version_impl(self.version, FDB_API_VERSION).orDie()
        self.debug("API version is \(self.version)")
    }

    /// Inits network and creates a dedicated phtread thread to run inner CFDB client routines
    private func initNetwork() throws -> FDB {
        class Box<T> {
            let value: T

            init(_ value: T) {
                self.value = value
            }
        }

        try fdb_setup_network().orThrow()
        self.debug("Network ready")

        let ptr = Unmanaged.passRetained(Box(self)).toOpaque()

        #if os(OSX)
            var thread: pthread_t?
        #else
            var thread: pthread_t = pthread_t()
        #endif

        pthread_create(
            &thread,
            nil,
            { ptr in
                fdb_run_network().orDie()
                #if os(OSX)
                    let _ptr = ptr
                #else
                    let _ptr = ptr!
                #endif
                Unmanaged<Box<FDB>>.fromOpaque(_ptr).takeRetainedValue().value.semaphore.signal()
                return nil
            },
            ptr
        )

        self.debug("Thread started")

        return self
    }

    /// Inits FDB cluster
    private func initCluster() throws -> FDB {
        let clusterFuture: Future = try fdb_create_cluster(self.clusterFile).waitForFuture()
        try fdb_future_get_cluster(clusterFuture.pointer, &self.cluster).orThrow()
        self.debug("Cluster ready")
        return self
    }

    /// Inits FDB database
    private func initDB() throws -> FDB {
        let dbFuture: Future = try fdb_cluster_create_database(
            self.cluster,
            FDB.dbName.utf8Start,
            Int32(FDB.dbName.utf8CodeUnitCount)
        ).waitForFuture()
        try fdb_future_get_database(dbFuture.pointer, &self.db).orThrow()
        self.debug("Database ready")
        return self
    }

    /// Performs all sanity checks after connection established and ensures that client and remote FDB server
    /// are healthy and ready to use
    private func checkIsAlive() throws -> FDB {
        guard let statusBytes = try self.get(key: [0xFF, 0xFF] + "/status/json".bytes) else {
            self.debug("Could not get system status key")
            throw FDB.Error.connectionError
        }
        guard let json = try JSONSerialization.jsonObject(with: Data(statusBytes)) as? [String: Any] else {
            self.debug("Could not parse JSON from system status: \(statusBytes)")
            throw FDB.Error.connectionError
        }
        guard
            let clientInfo = json["client"] as? [String: Any],
            let dbStatus = clientInfo["database_status"] as? [String: Bool],
            let available = dbStatus["available"],
            available == true
        else {
            self.debug("DB is not available according to system status info: \(json)")
            throw FDB.Error.connectionError
        }

        self.debug("Client is healthy")

        return self
    }

    /// Returns current FDB connection pointer or transparently connects if no connection is established yet
    internal func getDB() throws -> Database {
        if let db = self.db {
            return db
        }

        _ = try self
            .initNetwork()
            .initCluster()
            .initDB()
            .checkIsAlive()
        self.isConnected = true

        self.debug("Successfully connected to FoundationDB, DB is healthy")

        return try self.getDB()
    }

    /// Prints verbose debug message to stdout (if `FDB.verbose` is `true`)
    ///
    /// TODO: Migrate to Server Logging API when it's out
    internal static func debug(_ message: String) {
        if self.verbose {
            print("[FDB] \(message)")
        }
    }

    /// Prints verbose debug message to stdout (if `FDB.verbose` is `true`)
    internal func debug(_ message: String) {
        FDB.debug("[\(ObjectIdentifier(self).hashValue)] \(message)")
    }

    /// Performs explicit connection to FDB cluster
    public func connect() throws {
        _ = try self.getDB()
        self.debug("Connected")
    }

    /// Sets bytes to given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: bytes value
    public func set(key: AnyFDBKey, value: Bytes) throws {
        try self.withTransaction {
            try $0.set(key: key, value: value, commit: true) as Void
        }
    }

    /// Sets bytes to given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: bytes value
    public func setSync(key: AnyFDBKey, value: Bytes) throws {
        try self.set(key: key, value: value) as Void
    }

    /// Clears given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    public func clear(key: AnyFDBKey) throws {
        try self.withTransaction {
            try $0.clear(key: key, commit: true) as Void
        }
    }

    /// Clears given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    public func clearSync(key: AnyFDBKey) throws {
        try self.clear(key: key) as Void
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    public func clear(begin: AnyFDBKey, end: AnyFDBKey) throws {
        try self.withTransaction {
            try $0.clear(begin: begin, end: end, commit: true) as Void
        }
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    public func clearSync(begin: AnyFDBKey, end: AnyFDBKey) throws {
        try self.clear(begin: begin, end: end) as Void
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - range: Range key
    public func clear(range: FDB.RangeKey) throws {
        return try self.clear(begin: range.begin, end: range.end)
    }

    /// Clears keys in given subspace in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - subspace: Subspace to clear
    public func clear(subspace: Subspace) throws {
        return try self.clear(range: subspace.range)
    }

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    public func get(key: AnyFDBKey, snapshot: Bool = false) throws -> Bytes? {
        return try self.withTransaction {
            try $0.get(key: key, snapshot: snapshot, commit: true)
        }
    }

    /// Returns a range of keys and their respective values under given subspace
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - subspace: Subspace
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    public func get(subspace: Subspace, snapshot: Bool = false) throws -> KeyValuesResult {
        return try self.withTransaction {
            try $0.get(range: subspace.range, snapshot: snapshot)
        }
    }

    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    ///   - beginEqual: Should begin key also include exact key value
    ///   - beginOffset: Begin key offset
    ///   - endEqual: Should end key also include exact key value
    ///   - endOffset: End key offset
    ///   - limit: Limit returned key-value pairs (only relevant when `mode` is `.exact`)
    ///   - targetBytes: If non-zero, indicates a soft cap on the combined number of bytes of keys and values to return
    ///   - mode: The manner in which rows are returned (see `FDB.StreamingMode` docs)
    ///   - iteration: If `mode` is `.iterator`, this arg represent current read iteration (should start from 1)
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - reverse: If `true`, key-value pairs will be returned in reverse lexicographical order
    public func get(
        begin: AnyFDBKey,
        end: AnyFDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .wantAll,
        iteration: Int32 = 1,
        snapshot: Bool = false,
        reverse: Bool = false
    ) throws -> FDB.KeyValuesResult {
        return try self.withTransaction {
            try $0.get(
                begin: begin,
                end: end,
                beginEqual: beginEqual,
                beginOffset: beginOffset,
                endEqual: endEqual,
                endOffset: endOffset,
                limit: limit,
                targetBytes: targetBytes,
                mode: mode,
                iteration: iteration,
                snapshot: snapshot,
                reverse: reverse,
                commit: true
            )
        }
    }

    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - range: Range key
    ///   - beginEqual: Should begin key also include exact key value
    ///   - beginOffset: Begin key offset
    ///   - endEqual: Should end key also include exact key value
    ///   - endOffset: End key offset
    ///   - limit: Limit returned key-value pairs (only relevant when `mode` is `.exact`)
    ///   - targetBytes: If non-zero, indicates a soft cap on the combined number of bytes of keys and values to return
    ///   - mode: The manner in which rows are returned (see `FDB.StreamingMode` docs)
    ///   - iteration: If `mode` is `.iterator`, this arg represent current read iteration (should start from 1)
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - reverse: If `true`, key-value pairs will be returned in reverse lexicographical order
    public func get(
        range: FDB.RangeKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .wantAll,
        iteration: Int32 = 1,
        snapshot: Bool = false,
        reverse: Bool = false
    ) throws -> FDB.KeyValuesResult {
        return try self.get(
            begin: range.begin,
            end: range.end,
            beginEqual: beginEqual,
            beginOffset: beginOffset,
            endEqual: endEqual,
            endOffset: endOffset,
            limit: limit,
            targetBytes: targetBytes,
            mode: mode,
            iteration: iteration,
            snapshot: snapshot,
            reverse: reverse
        )
    }

    /// Peforms an atomic operation in FDB cluster on given key with given value bytes
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - op: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    public func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes) throws {
        try self.withTransaction {
            try $0.atomic(op, key: key, value: value, commit: true) as Void
        }
    }

    /// Peforms an atomic operation in FDB cluster on given key with given signed integer value
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - op: Atomic operation
    ///   - key: FDB key
    ///   - value: Integer
    public func atomic<T: SignedInteger>(_ op: FDB.MutationType, key: AnyFDBKey, value: T) throws {
        try self.atomic(op, key: key, value: getBytes(value))
    }

    /// Peforms a quasi-atomic increment operation in FDB cluster on given key with given integer
    ///
    /// This function will block current thread during execution
    ///
    /// Warning: though this function uses atomic `.add` increment, immediate serializable read of incremented key
    /// negates all benefits of atomicity, and therefore it shouldn't be considered truly atomical. However, it still
    /// works, and it gives you guarantees that only you will get the incremented value. It may lead to increased
    /// read conflicts on high load (hence lower performance), and is only usable when generating serial integer IDs.
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Integer
    @discardableResult public func increment(key: AnyFDBKey, value: Int64 = 1) throws -> Int64 {
        return try self.withTransaction { transaction in
            try transaction.atomic(.add, key: key, value: getBytes(value), commit: false) as Void

            guard let bytes: Bytes = try transaction.get(key: key) else {
                throw FDB.Error.unexpectedError("Couldn't get key '\(key)' after increment")
            }

            try transaction.commitSync()

            return bytes.cast()
        }
    }

    /// Peforms a quasi-atomic decrement operation in FDB cluster on given key with given integer
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Integer
    @discardableResult public func decrement(key: AnyFDBKey, value: Int64 = 1) throws -> Int64 {
        return try self.increment(key: key, value: -value)
    }
}
