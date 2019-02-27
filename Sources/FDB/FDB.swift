import CFDB
import Foundation
import NIO

public class FDB {
    internal typealias Cluster = OpaquePointer
    internal typealias Database = OpaquePointer

    /// Range get streaming mode
    public enum StreamingMode: Int32 {
        /// Client intends to consume the entire range and would like it all transferred as early as possible.
        ///
        /// aka `FDB_STREAMING_MODE_WANT_ALL`
        case wantAll = -2

        /// The default. The client doesn't know how much of the range it is likely to used and wants different
        /// performance concerns to be balanced. Only a small portion of data is transferred to the client initially
        /// (in order to minimize costs if the client doesn't read the entire range), and as the caller iterates over
        /// more items in the range larger batches will be transferred in order to minimize latency.
        ///
        /// aka `FDB_STREAMING_MODE_ITERATOR`
        case iterator = -1

        /// Infrequently used. The client has passed a specific row limit and wants that many rows delivered in
        /// a single batch. Because of iterator operation in client drivers make request batches transparent to
        /// the user, consider ``WANT_ALL`` StreamingMode instead. A row limit must be specified if this mode is used.
        ///
        /// aka `FDB_STREAMING_MODE_EXACT`
        case exact = 0

        /// Infrequently used. Transfer data in batches small enough to not be much more expensive than reading
        /// individual rows, to minimize cost if iteration stops early.
        ///
        /// aka `FDB_STREAMING_MODE_SMALL`
        case small = 1

        /// Infrequently used. Transfer data in batches sized in between small and large.
        ///
        /// aka `FDB_STREAMING_MODE_MEDIUM`
        case medium = 2

        /// Infrequently used. Transfer data in batches large enough to be, in a high-concurrency environment,
        /// nearly as efficient as possible. If the client stops iteration early, some disk and network bandwidth
        /// may be wasted. The batch size may still be too small to allow a single client to get high throughput from
        /// the database, so if that is what you need consider the SERIAL StreamingMode.
        ///
        /// aka `FDB_STREAMING_MODE_LARGE`
        case large = 3

        /// Transfer data in batches large enough that an individual client can get reasonable read bandwidth from
        /// the database. If the client stops iteration early, considerable disk and network bandwidth may be wasted.
        ///
        /// aka `FDB_STREAMING_MODE_SERIAL`
        case serial = 4
    }

    public enum MutationType: UInt32 {
        /// Performs an addition of little-endian integers. If the existing value in the database is not present or
        /// shorter than ``param``, it is first extended to the length of ``param`` with zero bytes.  If ``param``
        /// is shorter than the existing value in the database, the existing value is truncated to match the length
        /// of ``param``. The integers to be added must be stored in a little-endian representation.
        /// They can be signed in two's complement representation or unsigned. You can add to an integer at a known
        /// offset in the value by prepending the appropriate number of zero bytes to ``param`` and padding with zero
        /// bytes to match the length of the value. However, this offset technique requires that you know the addition
        /// will not cause the integer field within the value to overflow.
        ///
        /// aka `FDB_MUTATION_TYPE_ADD`
        case add = 2
        
        /// Performs a bitwise ``and`` operation.  If the existing value in the database is not present, then ``param``
        /// is stored in the database. If the existing value in the database is shorter than ``param``, it is first
        /// extended to the length of ``param`` with zero bytes.  If ``param`` is shorter than the existing value in
        /// the database, the existing value is truncated to match the length of ``param``.
        ///
        /// aka `FDB_MUTATION_TYPE_BIT_AND`
        case bitAnd = 6
        
        /// Performs a bitwise ``or`` operation.  If the existing value in the database is not present or shorter than
        /// ``param``, it is first extended to the length of ``param`` with zero bytes.  If ``param`` is shorter than
        /// the existing value in the database, the existing value is truncated to match the length of ``param``.
        ///
        /// aka `FDB_MUTATION_TYPE_BIT_OR`
        case bitOr = 7
        
        /// Performs a bitwise ``xor`` operation.  If the existing value in the database is not present or shorter than
        /// ``param``, it is first extended to the length of ``param`` with zero bytes.  If ``param`` is shorter than
        /// the existing value in the database, the existing value is truncated to match the length of ``param``.
        ///
        /// aka `FDB_MUTATION_TYPE_BIT_XOR`
        case bitXor = 8
        
        /// Appends ``param`` to the end of the existing value already in the database at the given key (or creates the
        /// key and sets the value to ``param`` if the key is empty). This will only append the value if the final
        /// concatenated value size is less than or equal to the maximum value size (i.e., if it fits).
        /// WARNING: No error is surfaced back to the user if the final value is too large because the mutation
        /// will not be applied until after the transaction has been committed. Therefore, it is only safe to use this
        /// mutation type if one can guarantee that one will keep the total value size under the maximum size.
        ///
        /// aka `FDB_MUTATION_TYPE_APPEND_IF_FITS`
        case appendIfFits = 9
        
        /// Performs a little-endian comparison of byte strings. If the existing value in the database is not present
        /// or shorter than ``param``, it is first extended to the length of ``param`` with zero bytes.  If ``param``
        /// is shorter than the existing value in the database, the existing value is truncated to match the length of
        /// ``param``. The larger of the two values is then stored in the database.
        ///
        /// aka `FDB_MUTATION_TYPE_MAX`
        case max = 12
        
        /// Performs a little-endian comparison of byte strings. If the existing value in the database is not present,
        /// then ``param`` is stored in the database. If the existing value in the database is shorter than ``param``,
        /// it is first extended to the length of ``param`` with zero bytes.  If ``param`` is shorter than the existing
        /// value in the database, the existing value is truncated to match the length of ``param``.
        /// The smaller of the two values is then stored in the database.
        ///
        /// aka `FDB_MUTATION_TYPE_MIN`
        case min = 13
        
        /// Transforms ``key`` using a versionstamp for the transaction. Sets the transformed key in the database to
        /// ``param``. The key is transformed by removing the final four bytes from the key and reading those as
        /// a little-Endian 32-bit integer to get a position ``pos``.
        /// The 10 bytes of the key from ``pos`` to ``pos + 10`` are replaced with the versionstamp of
        /// the transaction used. The first byte of the key is position 0. A versionstamp is a 10 byte, unique,
        /// monotonically (but not sequentially) increasing value for each committed transaction. The first 8 bytes are
        /// the committed version of the database (serialized in big-Endian order). The last 2 bytes are monotonic in
        /// the serialization order for transactions. WARNING: At this time, versionstamps are compatible with the Tuple
        /// layer only in the Java and Python bindings. Also, note that prior to API version 520, the offset was
        /// computed from only the final two bytes rather than the final four bytes.
        ///
        /// aka `FDB_MUTATION_TYPE_SET_VERSIONSTAMPED_KEY`
        case setVersionstampedKey = 14
        
        /// Transforms ``param`` using a versionstamp for the transaction. Sets the ``key`` given to the transformed
        /// ``param``. The parameter is transformed by removing the final four bytes from ``param`` and reading those
        /// as a little-Endian 32-bit integer to get a position ``pos``. The 10 bytes of the parameter
        /// from ``pos`` to ``pos + 10`` are replaced with the versionstamp of the transaction used.
        /// The first byte of the parameter is position 0. A versionstamp is a 10 byte, unique, monotonically
        /// (but not sequentially) increasing value for each committed transaction. The first 8 bytes are the committed
        /// version of the database (serialized in big-Endian order). The last 2 bytes are monotonic in
        /// the serialization order for transactions. WARNING: At this time, versionstamps are compatible with the Tuple
        /// layer only in the Java and Python bindings. Also, note that prior to API version 520, the versionstamp was
        /// always placed at the beginning of the parameter rather than computing an offset.
        ///
        /// aka `FDB_MUTATION_TYPE_SET_VERSIONSTAMPED_VALUE`
        case setVersionstampedValue = 15
        
        /// Performs lexicographic comparison of byte strings. If the existing value in the database is not present,
        /// then ``param`` is stored. Otherwise the smaller of the two values is then stored in the database.
        ///
        /// aka `FDB_MUTATION_TYPE_BYTE_MIN`
        case byteMin = 16
        
        /// Performs lexicographic comparison of byte strings. If the existing value in the database is not present,
        /// then ``param`` is stored. Otherwise the larger of the two values is then stored in the database.
        ///
        /// aka `FDB_MUTATION_TYPE_BYTE_MAX`
        case byteMax = 17
    }

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
            var thread: pthread_t? = nil
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
        let clusterFuture: Future<Void> = try fdb_create_cluster(self.clusterFile).waitForFuture()
        try fdb_future_get_cluster(clusterFuture.pointer, &self.cluster).orThrow()
        self.debug("Cluster ready")
        return self
    }

    /// Inits FDB database
    private func initDB() throws -> FDB {
        let dbFuture: Future<Void> = try fdb_cluster_create_database(
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
    private func getDB() throws -> Database {
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

    /// Begins a new FDB transaction without an event loop
    public func begin() throws -> FDB.Transaction {
        self.debug("Trying to start transaction without eventloop")

        return try FDB.Transaction.begin(try self.getDB())
    }

    /// Begins a new FDB transaction with given event loop
    ///
    /// - parameters:
    ///   - eventLoop: Swift-NIO EventLoop to run future computations
    /// - returns: `EventLoopFuture` with a transaction instance as future value.
    public func begin(eventLoop: EventLoop) -> EventLoopFuture<FDB.Transaction> {
        do {
            self.debug("Trying to start transaction with eventloop \(Swift.type(of: eventLoop))")

            return eventLoop.newSucceededFuture(
                result: try FDB.Transaction.begin(
                    try self.getDB(),
                    eventLoop
                )
            )
        } catch {
            self.debug("Failed to start transaction with eventloop \(Swift.type(of: eventLoop)): \(error)")
            return FDB.dummyEventLoop.newFailedFuture(error: error)
        }
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
        try self.begin().set(key: key, value: value, commit: true) as Void
    }

    /// Clears given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    public func clear(key: AnyFDBKey) throws {
        return try self.begin().clear(key: key, commit: true)
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    public func clear(begin: AnyFDBKey, end: AnyFDBKey) throws {
        return try self.begin().clear(begin: begin, end: end, commit: true)
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

    /// Returns bytes value for given key (or `nil` of no key)
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    public func get(key: AnyFDBKey, snapshot: Bool = false) throws -> Bytes? {
        return try self.begin().get(key: key, snapshot: snapshot, commit: true)
    }

    /// Returns a range of keys and their respective values under given subspace
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - subspace: Subspace
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    public func get(subspace: Subspace, snapshot: Bool = false) throws -> KeyValuesResult {
        return try self.begin().get(range: subspace.range, snapshot: snapshot)
    }

    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - subspace: Subspace
    ///   - begin: Begin key
    ///   - end: End key
    ///   - beginEqual: Should begin key also include exact key value
    ///   - beginOffset: Begin key offset
    ///   - endEqual: Should end key also include exact key value
    ///   - endOffset: End key offset
    ///   - limit: Limit returned key-value pairs (only relevant when `mode` is `.exact`)
    ///   - targetBytes: If non-zero, indicates a soft cap on the combined number of bytes of keys and values to return
    ///   - mode: The manner in which rows are returned (see `FDB.StreamingMode` docs)
    ///   - iteration: if `mode` is `.iterator` this arg represent current read iteration (should start from 1)
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - reverse: if `true`, key-value pairs will be returned in reverse lexicographical order
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
        return try self.begin().get(
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
    ///   - iteration: if `mode` is `.iterator` this arg represent current read iteration (should start from 1)
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - reverse: if `true`, key-value pairs will be returned in reverse lexicographical order
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
        try self.begin().atomic(op, key: key, value: value, commit: true) as Void
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
        let transaction = try self.begin()
        try transaction.atomic(.add, key: key, value: getBytes(value), commit: false) as Void
        guard let bytes: Bytes = try transaction.get(key: key) else {
            throw FDB.Error.unexpectedError
        }
        try transaction.commitSync()
        return bytes.cast()
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
