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

    static let dbName: StaticString = "DB"

    let version: Int32
    let networkStopTimeout: Int
    let clusterFile: String
    var cluster: Cluster? = nil
    var db: Database? = nil
    let queue: DispatchQueue

    public var verbose = false

    let semaphore = DispatchSemaphore(value: 0)

    public required init(
        cluster: String,
        networkStopTimeout: Int = 10,
        version: Int32 = FDB_API_VERSION,
        queue: DispatchQueue = DispatchQueue(label: "fdb", qos: .userInitiated, attributes: .concurrent)
    ) {
        self.clusterFile = cluster
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
            print(message)
        }
    }

    public func begin() throws -> Transaction {
        return try Transaction.begin(try self.getDB())
    }

    public func connect() throws {
        let _ = try self.getDB()
    }

    @discardableResult public func set(
        key: FDBKey,
        value: Bytes,
        transaction: Transaction? = nil,
        commit: Bool = true
    ) throws -> Transaction? {
        let tr = try transaction ?? self.begin()
        try tr.set(key: key, value: value, commit: commit)
        return commit ? nil : tr
    }

    public func get(
        key: FDBKey,
        transaction: Transaction? = nil,
        snapshot: Int32 = 0,
        commit: Bool = true
    ) throws -> Bytes? {
        return try (transaction ?? self.begin()).get(key: key, snapshot: snapshot, commit: commit)
    }

    public func clear(key: FDBKey, transaction: Transaction? = nil, commit: Bool = true) throws {
        return try (transaction ?? self.begin()).clear(key: key, commit: commit)
    }

    public func clear(begin: FDBKey, end: FDBKey, transaction: Transaction? = nil, commit: Bool = true) throws {
        return try (transaction ?? self.begin()).clear(begin: begin, end: end, commit: commit)
    }

    public func clear(range: RangeFDBKey, transaction: Transaction? = nil, commit: Bool = true) throws {
        return try self.clear(begin: range.begin, end: range.end, transaction: transaction, commit: commit)
    }

    public func get(
        range: RangeFDBKey,
        transaction: Transaction? = nil,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .WantAll,
        iteration: Int32 = 1,
        snapshot: Int32 = 0,
        reverse: Bool = false,
        commit: Bool = true
    ) throws -> [KeyValue] {
        return try self.get(
            begin: range.begin,
            end: range.end,
            transaction: transaction,
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
            commit: commit
        )
    }

    public func get(
        begin: FDBKey,
        end: FDBKey,
        transaction: Transaction? = nil,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .WantAll,
        iteration: Int32 = 1,
        snapshot: Int32 = 0,
        reverse: Bool = false,
        commit: Bool = true
    ) throws -> [KeyValue] {
        return try (transaction ?? self.begin()).get(
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
            commit: commit
        )
    }
}
