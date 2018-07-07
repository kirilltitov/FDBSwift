import CFDB
import Dispatch

public typealias Byte = UInt8
public typealias Bytes = [Byte]

public class FDB {
    public typealias Cluster = OpaquePointer
    public typealias Database = OpaquePointer

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
        key: Bytes,
        value: Bytes,
        transaction: Transaction? = nil,
        commit: Bool = true
    ) throws -> Transaction? {
        let tr = try transaction ?? self.begin()
        try tr.set(key: key, value: value, commit: commit)
        return commit ? nil : tr
    }

    @discardableResult public func set(
        key: String,
        value: Bytes,
        transaction: Transaction? = nil,
        commit: Bool = true
    ) throws -> Transaction? {
        return try self.set(key: key.bytes, value: value, transaction: transaction, commit: commit)
    }

    public func get(
        key: Bytes,
        transaction: Transaction? = nil,
        snapshot: Int32 = 0,
        commit: Bool = true
    ) throws -> Bytes? {
        return try (transaction ?? self.begin()).get(key: key, snapshot: snapshot, commit: commit)
    }

    public func get(
        key: String,
        transaction: Transaction? = nil,
        snapshot: Int32 = 0,
        commit: Bool = true
    ) throws -> Bytes? {
        return try self.get(key: key.bytes, transaction: transaction, snapshot: snapshot, commit: commit)
    }

    public func remove(key: Bytes, transaction: Transaction? = nil, commit: Bool = true) throws {
        return try (transaction ?? self.begin()).clear(key: key, commit: commit)
    }

    public func remove(key: String, transaction: Transaction? = nil, commit: Bool = true) throws {
        return try self.remove(key: key.bytes, transaction: transaction, commit: commit)
    }
}
