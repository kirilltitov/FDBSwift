import Foundation
import LGNLog
import CFDB

public final class FDB: AnyFDB {
    internal typealias Cluster = OpaquePointer
    internal typealias Database = OpaquePointer

    private static let dbName: StaticString = "DB"

    private let version: Int32 = FDB_API_VERSION
    private let networkStopTimeout: Int
    private let clusterFile: String
    private var cluster: FDB.Cluster?
    private var db: FDB.Database?

    private var isConnected = false

    @available(*, deprecated, message: "Use Logger.current instead")
    public static var logger: Logger = {
        Logger.current
    }()

    private let semaphore = DispatchSemaphore(value: 0)

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

        Logger.current.debug("Using cluster file '\(self.clusterFile)'")
        Logger.current.debug("Network stop timeout is \(self.networkStopTimeout) seconds")

        self.selectAPIVersion()
    }

    deinit {
        Logger.current.debug("Deinit started")
        if self.isConnected {
            self.disconnect()
        }
    }

    public func disconnect() {
        if !self.isConnected {
            Logger.current.error("Trying to disconnect from FDB while not connected")
            return
        }
        fdb_stop_network().orDie()
        if self.semaphore.wait(for: self.networkStopTimeout) == .timedOut {
            Logger.current.critical("Stop network timeout (\(self.networkStopTimeout) seconds)")
            exit(1)
        }
        Logger.current.debug("Network stopped")
        fdb_database_destroy(self.db)
        Logger.current.debug("Cluster and database destroyed")
        self.isConnected = false
    }

    /// Selects an API version
    ///
    /// Warning: API version must be less or equal to one that defined in `fdb_c.h` header file.
    ///
    /// Warning 2: must be called before any other call.
    private func selectAPIVersion() {
        fdb_select_api_version_impl(self.version, FDB_API_VERSION).orDie()
        Logger.current.debug("API version is \(self.version)")
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
        Logger.current.debug("Network ready")

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
                Logger.current.debug("Starting network")
                fdb_run_network().orDie()
                Logger.current.debug("Stopping network")
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

        Logger.current.debug("Thread started")

        return self
    }

    /// Inits FDB database
    private func initDB() throws -> FDB {
        try fdb_create_database(self.clusterFile, &self.db).orThrow()

        Logger.current.debug("Database ready")

        return self
    }

    /// Performs all sanity checks after connection established and ensures that client and remote FDB server
    /// are healthy and ready to use
    ///
    /// Will block current thread during execution (on first call) while waiting for status response from FDB server
    ///
    private func checkIsAlive() throws -> FDB {
        let tr = try self.begin()

        guard let tr = tr as? FDB.Transaction else {
            Logger.current.debug("Transaction in \(#function) is not \(FDB.Transaction.self), assuming that DB is alive")
            return self
        }

        guard let statusBytes: Bytes = try tr.get(key: [0xFF, 0xFF] + "/status/json".bytes).wait() else {
            Logger.current.critical("Could not get system status key")
            throw FDB.Error.connectionError
        }
        guard let json = try JSONSerialization.jsonObject(with: Data(statusBytes)) as? [String: Any] else {
            Logger.current.critical("Could not parse JSON from system status: \(statusBytes)")
            throw FDB.Error.connectionError
        }
        guard
            let clientInfo = json["client"] as? [String: Any],
            let dbStatus = clientInfo["database_status"] as? [String: Bool],
            let available = dbStatus["available"],
            available == true
        else {
            Logger.current.critical("DB is not available according to system status info: \(json)")
            throw FDB.Error.connectionError
        }

        Logger.current.debug("Client is healthy")

        return self
    }

    /// Returns current FDB connection pointer or transparently connects if no connection is established yet
    internal func getDB() throws -> Database {
        if let db = self.db {
            return db
        }

        _ = try self
            .initNetwork()
            .initDB()
            .checkIsAlive()
        self.isConnected = true

        Logger.current.debug("Successfully connected to FoundationDB, DB is healthy")

        return try self.getDB()
    }

    public func connect() throws {
        _ = try self.getDB()
        Logger.current.debug("Connected")
    }
}
