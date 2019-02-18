import CFDB
import Foundation
import NIO

public class FDB {
    public typealias Cluster = OpaquePointer
    public typealias Database = OpaquePointer

    public enum StreamingMode: Int32 {
        case wantAll  = -2 // FDB_STREAMING_MODE_WANT_ALL
        case iterator = -1 // FDB_STREAMING_MODE_ITERATOR
        case exact    =  0 // FDB_STREAMING_MODE_EXACT
        case small    =  1 // FDB_STREAMING_MODE_SMALL
        case medium   =  2 // FDB_STREAMING_MODE_MEDIUM
        case large    =  3 // FDB_STREAMING_MODE_LARGE
        case serial   =  4 // FDB_STREAMING_MODE_SERIAL
    }

    public enum MutationType: UInt32 {
        case add                    = 2  // FDB_MUTATION_TYPE_ADD
        case bitAnd                 = 6  // FDB_MUTATION_TYPE_BIT_AND
        case bitOr                  = 7  // FDB_MUTATION_TYPE_BIT_OR
        case bitXor                 = 8  // FDB_MUTATION_TYPE_BIT_XOR
        case appendIfFits           = 9  // FDB_MUTATION_TYPE_APPEND_IF_FITS
        case max                    = 12 // FDB_MUTATION_TYPE_MAX
        case min                    = 13 // FDB_MUTATION_TYPE_MIN
        case setVersionstampedKey   = 14 // FDB_MUTATION_TYPE_SET_VERSIONSTAMPED_KEY
        case setVersionstampedValue = 15 // FDB_MUTATION_TYPE_SET_VERSIONSTAMPED_VALUE
        case byteMin                = 16 // FDB_MUTATION_TYPE_BYTE_MIN
        case byteMax                = 17 // FDB_MUTATION_TYPE_BYTE_MAX
    }

    private static let dbName: StaticString = "DB"

    internal static let dummyEventLoop = EmbeddedEventLoop()

    private let version: Int32
    private let networkStopTimeout: Int
    private let clusterFile: String
    private var cluster: FDB.Cluster?
    private var db: FDB.Database?

    private var isConnected = false

    public var verbose = false

    private let semaphore = DispatchSemaphore(value: 0)

    public init(
        cluster: String? = nil,
        networkStopTimeout: Int = 10,
        version: Int32 = FDB_API_VERSION
    ) {
        if let cluster = cluster {
            self.clusterFile = cluster
        } else {
            #if os(macOS)
                self.clusterFile = "/usr/local/etc/foundationdb/fdb.cluster"
            #else // assuming that else is linux
                self.clusterFile = "/etc/foundationdb/fdb.cluster"
            #endif
        }
        self.networkStopTimeout = networkStopTimeout
        self.version = version
    }

    deinit {
        self.debug("Deinit started")
        if self.isConnected {
            self.disconnect()
        }
    }

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

    private func selectAPIVersion() throws -> FDB {
        self.debug("API version is \(self.version)")
        try fdb_select_api_version_impl(self.version, FDB_API_VERSION).orThrow()
        return self
    }

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

        return self
    }

    private func initCluster() throws -> FDB {
        let clusterFuture: Future<Void> = try fdb_create_cluster(self.clusterFile).waitForFuture()
        try fdb_future_get_cluster(clusterFuture.pointer, &self.cluster).orThrow()
        self.debug("Cluster ready")
        return self
    }

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

    private func checkIsAlive() throws -> FDB {
        guard let statusBytes = try self.get(key: [0xFF, 0xFF] + "/status/json".bytes) else {
            throw FDB.Error.connectionError
        }
        guard let json = try JSONSerialization.jsonObject(with: Data(statusBytes)) as? [String: Any] else {
            throw FDB.Error.connectionError
        }
        guard
            let clientInfo = json["client"] as? [String: Any],
            let dbStatus = clientInfo["database_status"] as? [String: Bool],
            let available = dbStatus["available"],
            available == true
        else {
            throw FDB.Error.connectionError
        }
        self.debug("Client is healthy")
        return self
    }

    private func getDB() throws -> Database {
        if let db = self.db {
            return db
        }
        _ = try self
            .selectAPIVersion()
            .initNetwork()
            .initCluster()
            .initDB()
            .checkIsAlive()
        self.isConnected = true
        return try self.getDB()
    }

    internal func debug(_ message: String) {
        if self.verbose {
            print("[FDB \(ObjectIdentifier(self))] \(message)")
        }
    }

    public func begin() throws -> FDB.Transaction {
        return try FDB.Transaction.begin(try self.getDB())
    }

    public func begin(eventLoop: EventLoop) -> EventLoopFuture<FDB.Transaction> {
        do {
            return eventLoop.newSucceededFuture(
                result: try FDB.Transaction.begin(
                    try self.getDB(),
                    eventLoop
                )
            )
        } catch {
            return FDB.dummyEventLoop.newFailedFuture(error: error)
        }
    }

    public func connect() throws {
        _ = try self.getDB()
        self.debug("Connected")
    }

    public func set(key: AnyFDBKey, value: Bytes) throws {
        try self.begin().set(key: key, value: value, commit: true) as Void
    }

    public func clear(key: AnyFDBKey) throws {
        return try self.begin().clear(key: key, commit: true)
    }

    public func clear(begin: AnyFDBKey, end: AnyFDBKey) throws {
        return try self.begin().clear(begin: begin, end: end, commit: true)
    }

    public func clear(range: FDB.RangeKey) throws {
        return try self.clear(begin: range.begin, end: range.end)
    }

    public func clear(subspace: Subspace) throws {
        return try self.clear(range: subspace.range)
    }

    public func get(key: AnyFDBKey, snapshot: Int32 = 0) throws -> Bytes? {
        return try self.begin().get(key: key, snapshot: snapshot, commit: true)
    }

    public func get(subspace: Subspace, snapshot: Int32 = 0) throws -> KeyValuesResult {
        return try self.begin().get(range: subspace.range, snapshot: snapshot)
    }

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
        snapshot: Int32 = 0,
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
        snapshot: Int32 = 0,
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

    public func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes) throws {
        try self.begin().atomic(op, key: key, value: value, commit: true) as Void
    }

    public func atomic<T: SignedInteger>(_ op: FDB.MutationType, key: AnyFDBKey, value: T) throws {
        try self.atomic(op, key: key, value: getBytes(value))
    }

    @discardableResult public func increment(key: AnyFDBKey, value: Int64 = 1) throws -> Int64 {
        let transaction = try self.begin()
        try transaction.atomic(.add, key: key, value: getBytes(value), commit: false) as Void
        guard let bytes: Bytes = try transaction.get(key: key) else {
            throw FDB.Error.unexpectedError
        }
        try transaction.commitSync()
        return bytes.cast()
    }

    @discardableResult public func decrement(key: AnyFDBKey, value: Int64 = 1) throws -> Int64 {
        return try self.increment(key: key, value: -value)
    }
}
