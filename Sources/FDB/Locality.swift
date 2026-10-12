import CFDB

// MARK: - Locality

extension FDB.Transaction {
    /// Returns the public network addresses (`ip:port`) of the storage servers holding given key
    public func getAddresses(for key: some FDB.Key) -> FDB.Future<[String]> {
        let key = key.fdbKey
        return FDB.Future(fdb_transaction_get_addresses_for_key(self.pointer, key, Int32(key.count))) {
            (pointer) throws(FDB.Error) -> [String] in
            var strings: UnsafeMutablePointer<UnsafePointer<CChar>?>?
            var count: Int32 = 0
            try fdb_future_get_string_array(pointer, &strings, &count).check()
            guard let strings else {
                return []
            }
            return (0 ..< Int(count)).compactMap { strings[$0].map { String(cString: $0) } }
        }
    }
}

extension FDB.Database {
    static let keyServersPrefix: Bytes = [0xFF] + Bytes("/keyServers/".utf8)

    /// Returns the keys at which the shards of given range begin, i.e. the boundaries of data distribution.
    ///
    /// Useful to split a large scan into parallel chunks, each served by different storage servers. The first key
    /// is the beginning of the shard containing `range.begin` if that's a shard boundary, otherwise the first
    /// boundary after it.
    ///
    /// Reads the system key space with snapshot reads in as many transactions as needed (if one becomes too old,
    /// the scan continues in a new one), so the result is not necessarily consistent with any single version.
    public func getBoundaryKeys(in range: FDB.KeyRange) async throws(FDB.Error) -> [Bytes] {
        var result: [Bytes] = []
        var begin = range.begin
        var transaction = try self.makeTransaction()

        while begin.lexicographicallyPrecedes(range.end) {
            let lastBegin = begin
            do {
                try transaction.setOption(.readSystemKeys)
                try transaction.setOption(.lockAware)
                let records = try await transaction.getAll(
                    FDB.KeyRange(begin: Self.keyServersPrefix + begin, end: Self.keyServersPrefix + range.end),
                    snapshot: true
                )
                for record in records {
                    let key = Bytes(record.key.dropFirst(Self.keyServersPrefix.count))
                    result.append(key)
                    begin = key + [0x00]
                }
                begin = range.end
            } catch {
                if error == .transactionTooOld, begin != lastBegin {
                    // Some progress has been made, continue with a fresh transaction
                    transaction = try self.makeTransaction()
                } else {
                    try await transaction.onError(error).value
                }
            }
        }
        return result
    }
}

// MARK: - Conflicting keys

extension FDB.Transaction {
    static let conflictingKeysPrefix: Bytes = [0xFF, 0xFF] + Bytes("/transaction/conflicting_keys/".utf8)

    /// Returns the key ranges which caused the last commit of this transaction to fail with
    /// ``FDB/Error/notCommitted``.
    ///
    /// Requires ``FDB/TransactionOption/reportConflictingKeys`` to be set before the commit (or
    /// ``FDB/DatabaseOption/transactionReportConflictingKeys`` for all transactions of a database). Must be called
    /// before the transaction is reset, so it's meant for manually managed transactions:
    ///
    /// ```swift
    /// let tr = try db.makeTransaction()
    /// try tr.setOption(.reportConflictingKeys)
    /// ...
    /// do {
    ///     try await tr.commit().value
    /// } catch .notCommitted {
    ///     logger.info("Conflict on \(try await tr.getConflictingKeys())")
    ///     try await tr.onError(.notCommitted).value
    /// }
    /// ```
    public func getConflictingKeys() async throws(FDB.Error) -> [FDB.KeyRange] {
        let prefix = Self.conflictingKeysPrefix
        let records = try await self.getAll(FDB.KeyRange(begin: prefix, end: prefix + [0xFF]))

        // Boundaries: a key with value "1" begins a conflicting range, the next one (with "0") ends it
        var result: [FDB.KeyRange] = []
        var begin: Bytes?
        for record in records {
            let key = Bytes(record.key.dropFirst(prefix.count))
            if record.value == [UInt8(ascii: "1")] {
                begin = key
            } else if let rangeBegin = begin {
                result.append(FDB.KeyRange(begin: rangeBegin, end: key))
                begin = nil
            }
        }
        return result
    }
}
