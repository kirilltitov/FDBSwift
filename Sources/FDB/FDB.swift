import CFDB
import Dispatch

public class FDB {
    public typealias Cluster = OpaquePointer
    public typealias Database = OpaquePointer

    static let dbName: StaticString = "DB"

    let version: Int32
    let networkStopTimeout: Int
    let clusterFile: String
    var cluster: Cluster? = nil
    var db: Database? = nil

    public var verbose = false

    let queue = DispatchQueue(label: "fdb", qos: .userInitiated, attributes: .concurrent)
    let semaphore = DispatchSemaphore(value: 0)

    public required init(cluster: String, networkStopTimeout: Int = 10, version: Int32 = FDB_API_VERSION) {
        self.clusterFile = cluster
        self.networkStopTimeout = networkStopTimeout
        self.version = version
    }

    deinit {
        self.debug("Deinit started")
        let networkErrno = fdb_stop_network()
        guard networkErrno == 0 else {
            print("Stop network error: [\(networkErrno)] \(getErrorInfo(for: networkErrno))")
            exit(1)
        }
        if self.semaphore.wait(timeout: .init(secondsFromNow: self.networkStopTimeout)) == .timedOut {
            print("Stop network timeout (\(self.networkStopTimeout) seconds)")
            exit(1)
        }
        self.debug("Network stopped")
        fdb_database_destroy(self.db)
        fdb_cluster_destroy(self.cluster)
        self.debug("Cluster and database destroyed")
    }

    private func selectApiVersion() throws {
        self.debug("API version is \(self.version)")
        let apiErrno = fdb_select_api_version_impl(self.version, FDB_API_VERSION)
        guard apiErrno == 0 else {
            throw Error.ApiError(getErrorInfo(for: apiErrno), apiErrno)
        }
    }

    private func initNetwork() throws {
        let setupErrno = fdb_setup_network()
        guard setupErrno == 0 else {
            throw Error.NetworkError(getErrorInfo(for: setupErrno), setupErrno)
        }
        self.debug("Network ready")
        self.queue.async {
            let networkErrno = fdb_run_network()
            guard networkErrno == 0 else {
                fatalError("Could not setup FoundationDB network: [\(networkErrno)] \(getErrorInfo(for: networkErrno))")
            }
            self.semaphore.signal()
        }
    }

    private func initCluster() throws {
        let clusterFuture = try fdb_create_cluster(self.clusterFile).waitForFuture()
        let clusterErrno = fdb_future_get_cluster(clusterFuture.pointer, &self.cluster)
        guard clusterErrno == 0 else {
            throw Error.ClusterError(getErrorInfo(for: clusterErrno), clusterErrno)
        }
    }

    private func initDB() throws {
        let dbFuture = try fdb_cluster_create_database(
            self.cluster,
            FDB.dbName.utf8Start,
            Int32(FDB.dbName.utf8CodeUnitCount)
        ).waitForFuture()
        let dbErrno = fdb_future_get_database(dbFuture.pointer, &self.db)
        guard dbErrno == 0 else {
            throw Error.DBError(getErrorInfo(for: dbErrno), dbErrno)
        }
    }

    private func getDB() throws -> Database {
        if let db = self.db {
            return db
        }
        try self.selectApiVersion()
        try self.initNetwork()
        try self.initCluster()
        try self.initDB()
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
