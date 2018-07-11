import CFDB
import Dispatch

public typealias Byte = UInt8
public typealias Bytes = [Byte]

public class FDB {
    public typealias Cluster = OpaquePointer
    public typealias Database = OpaquePointer

    public enum StreamingMode: Int32 {
        case WantAll  = -2 // FDB_STREAMING_MODE_WANT_ALL
        case Iterator = -1 // FDB_STREAMING_MODE_ITERATOR
        case Exact    =  0 // FDB_STREAMING_MODE_EXACT
        case Small    =  1 // FDB_STREAMING_MODE_SMALL
        case Medium   =  2 // FDB_STREAMING_MODE_MEDIUM
        case Large    =  3 // FDB_STREAMING_MODE_LARGE
        case Serial   =  4 // FDB_STREAMING_MODE_SERIAL
    }

    static private let dbName: StaticString = "DB"

    private let version: Int32
    private let networkStopTimeout: Int
    private let clusterFile: String
    private var cluster: Cluster? = nil
    private var db: Database? = nil
    private let queue: DispatchQueue

    public var verbose = false

    private let semaphore = DispatchSemaphore(value: 0)

    public required init(
        cluster: String? = nil,
        networkStopTimeout: Int = 10,
        version: Int32 = FDB_API_VERSION,
        queue: DispatchQueue = DispatchQueue(label: "fdb", qos: .userInitiated, attributes: .concurrent)
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
        self.queue = queue
    }

    deinit {
        self.debug("Deinit started")
        fdb_stop_network().orDie()
        if self.semaphore.wait(for: self.networkStopTimeout) == .timedOut {
            print("Stop network timeout (\(self.networkStopTimeout) seconds)")
            exit(1)
        }
        self.debug("Network stopped")
        fdb_database_destroy(self.db)
        fdb_cluster_destroy(self.cluster)
        self.debug("Cluster and database destroyed")
    }

    private func selectApiVersion() throws -> FDB {
        self.debug("API version is \(self.version)")
        try fdb_select_api_version_impl(self.version, FDB_API_VERSION).orThrow()
        return self
    }

    private func initNetwork() throws -> FDB {
        try fdb_setup_network().orThrow()
        self.debug("Network ready")
        self.queue.async {
            fdb_run_network().orDie()
            self.semaphore.signal()
        }
        return self
    }

    private func initCluster() throws -> FDB {
        let clusterFuture = try fdb_create_cluster(self.clusterFile).waitForFuture()
        try fdb_future_get_cluster(clusterFuture.pointer, &self.cluster).orThrow()
        return self
    }

    private func initDB() throws {
        let dbFuture = try fdb_cluster_create_database(
            self.cluster,
            FDB.dbName.utf8Start,
            Int32(FDB.dbName.utf8CodeUnitCount)
        ).waitForFuture()
        try fdb_future_get_database(dbFuture.pointer, &self.db).orThrow()
    }

    private func getDB() throws -> Database {
        if let db = self.db {
            return db
        }
        try self
            .selectApiVersion()
            .initNetwork()
            .initCluster()
            .initDB()
        return try self.getDB()
    }

    private func debug(_ message: String) {
        if self.verbose {
            print("[FDB \(ObjectIdentifier(self))] \(message)")
        }
    }

    public func begin() throws -> Transaction {
        return try Transaction.begin(try self.getDB())
    }

    public func connect() throws {
        let _ = try self.getDB()
    }

    public func set(key: FDBKey, value: Bytes) throws {
        try self.begin().set(key: key, value: value, commit: true)
    }

    public func clear(key: FDBKey) throws {
        return try self.begin().clear(key: key, commit: true)
    }

    public func clear(begin: FDBKey, end: FDBKey) throws {
        return try self.begin().clear(begin: begin, end: end, commit: true)
    }

    public func clear(range: RangeFDBKey) throws {
        return try self.clear(begin: range.begin, end: range.end)
    }

    public func clear(subspace: Subspace) throws {
        return try self.clear(range: subspace.range)
    }

    public func get(key: FDBKey, snapshot: Int32 = 0) throws -> Bytes? {
        return try self.begin().get(key: key, snapshot: snapshot, commit: true)
    }

    public func get(subspace: Subspace, snapshot: Int32 = 0) throws -> [KeyValue] {
        return try self.begin().get(range: subspace.range, snapshot: snapshot)
    }

    public func get(
        begin: FDBKey,
        end: FDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .WantAll,
        iteration: Int32 = 1,
        snapshot: Int32 = 0,
        reverse: Bool = false
    ) throws -> [KeyValue] {
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
        range: RangeFDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .WantAll,
        iteration: Int32 = 1,
        snapshot: Int32 = 0,
        reverse: Bool = false
    ) throws -> [KeyValue] {
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
}
