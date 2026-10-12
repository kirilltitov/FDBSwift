import CFDB

extension FDB.Database {
    /// How busy the client's network thread is: a value between 0 (idle) and 1 (fully busy), averaged over the last
    /// second. Values close to 1 mean the client can't keep up, and more clients (processes) are needed.
    public var mainThreadBusyness: Double {
        fdb_database_get_main_thread_busyness(self.pointer)
    }

    /// Returns the status of the client's connections to the cluster as a JSON document
    /// (connected coordinators, proxies, failures etc.), useful for diagnostics
    public func getClientStatus() -> FDB.Future<Bytes> {
        .key(fdb_database_get_client_status(self.pointer))
    }

    /// Returns the protocol version of the cluster.
    ///
    /// - parameters:
    ///   - expectedVersion: If given, the future completes only when the protocol version differs from it
    ///     (e.g. to wait for an upgrade)
    public func getServerProtocol(expectedVersion: UInt64? = nil) -> FDB.Future<UInt64> {
        FDB.Future(fdb_database_get_server_protocol(self.pointer, expectedVersion ?? 0)) {
            (pointer) throws(FDB.Error) -> UInt64 in
            var value: UInt64 = 0
            try fdb_future_get_uint64(pointer, &value).check()
            return value
        }
    }

    /// Reboots the worker process at given address (`ip:port`, as listed by `fdbcli`'s `kill` command).
    ///
    /// - parameters:
    ///   - check: Reboot only if the process is not needed for availability or durability
    ///   - duration: Suspend the process for this many seconds before restarting it (0 restarts immediately)
    /// - returns: Whether the request was accepted
    public func rebootWorker(address: String, check: Bool = false, duration: Int32 = 0) -> FDB.Future<Bool> {
        let address = Bytes(address.utf8)
        return FDB.Future(
            fdb_database_reboot_worker(self.pointer, address, Int32(address.count), check ? 1 : 0, duration)
        ) { (pointer) throws(FDB.Error) -> Bool in
            var value: Int64 = 0
            try fdb_future_get_int64(pointer, &value).check()
            return value != 0
        }
    }

    /// Forces the cluster to recover in given datacenter, **accepting the loss of** all mutations not yet replicated
    /// there. A disaster recovery tool for multi-region clusters, see FoundationDB documentation before using it.
    public func forceRecoveryWithDataLoss(datacenterID: String) -> FDB.Future<Void> {
        let id = Bytes(datacenterID.utf8)
        return FDB.Future(fdb_database_force_recovery_with_data_loss(self.pointer, id, Int32(id.count)))
    }

    /// Creates a disk snapshot of the cluster, see the FoundationDB documentation on disk snapshot backups.
    ///
    /// - parameters:
    ///   - uid: Unique ID of the snapshot (32 hex characters)
    ///   - command: Snapshot command (`path-to-binary arg1=value1 ...`) to run on every process
    public func createSnapshot(uid: String, command: String) -> FDB.Future<Void> {
        let uid = Bytes(uid.utf8)
        let command = Bytes(command.utf8)
        return FDB.Future(
            fdb_database_create_snapshot(self.pointer, uid, Int32(uid.count), command, Int32(command.count))
        )
    }
}
