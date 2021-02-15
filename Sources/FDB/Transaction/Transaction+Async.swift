import CFDB

public extension FDB.Transaction {
    func commit() async throws {
        let future: FDB.Future = try await self.commit().ready()
        let commitError = fdb_future_get_error(future.pointer)
        guard commitError == 0 else {
            let retryFuture: FDB.Future = try await fdb_transaction_on_error(self.pointer, commitError).futureReady()
            try fdb_future_get_error(retryFuture.pointer).orThrow()
            throw FDB.Error.transactionRetry(transaction: self)
        }
    }

    func set(versionstampedKey: AnyFDBKey, value: Bytes) throws {
        var serializedKey = versionstampedKey.asFDBKey()
        let offset = try FDB.Tuple.offsetOfFirstIncompleteVersionstamp(from: serializedKey)
        serializedKey.append(contentsOf: getBytes(offset.littleEndian))

        self.atomic(.setVersionstampedKey, key: serializedKey, value: value)
    }

    func get(key: AnyFDBKey, snapshot: Bool) async throws -> Bytes? {
        try await self.get(key: key, snapshot: snapshot).bytes()
    }

    func get(key: AnyFDBKey) async throws -> Bytes? {
        try await self.get(key: key, snapshot: false)
    }

    func get(range: FDB.RangeKey, snapshot: Bool) async throws -> FDB.KeyValuesResult {
        try await self.get(
            range: range,
            beginEqual: true,
            beginOffset: 0,
            endEqual: true,
            endOffset: 0,
            limit: 0,
            targetBytes: 0,
            mode: .wantAll,
            iteration: 0,
            snapshot: snapshot,
            reverse: false
        )
    }

    func get(
        begin: AnyFDBKey,
        end: AnyFDBKey,
        beginEqual: Bool,
        beginOffset: Int32,
        endEqual: Bool,
        endOffset: Int32,
        limit: Int32,
        targetBytes: Int32,
        mode: FDB.StreamingMode,
        iteration: Int32,
        snapshot: Bool,
        reverse: Bool
    ) async throws -> FDB.KeyValuesResult {
        try await self.get(
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
            reverse: reverse
        ).keyValues()
    }

    func get(
        range: FDB.RangeKey,
        beginEqual: Bool,
        beginOffset: Int32,
        endEqual: Bool,
        endOffset: Int32,
        limit: Int32,
        targetBytes: Int32,
        mode: FDB.StreamingMode,
        iteration: Int32,
        snapshot: Bool,
        reverse: Bool
    ) async throws -> FDB.KeyValuesResult {
        try await self.get(
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
        ).keyValues()
    }

    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T) {
        self.atomic(op, key: key, value: getBytes(value))
    }

    func getReadVersion() async throws -> Int64 {
        try await self.getReadVersion().int64()
    }

    func getVersionstamp() async throws -> FDB.Versionstamp {
        let future: FDB.Future = self.getVersionstamp()

        try await self.commit()

        let bytes = try await future.keyBytes()

        guard bytes.count == 10 else {
            self.log("[getVersionstamp] Bytes that do not represent a versionstamp were returned: \(String(describing: bytes))", level: .error)
            throw FDB.Error.invalidVersionstamp
        }

        let transactionCommitVersion = try! UInt64(bigEndian: Bytes(bytes[0..<8]).cast())
        let batchNumber = try! UInt16(bigEndian: Bytes(bytes[8..<10]).cast())

        return FDB.Versionstamp(transactionCommitVersion: transactionCommitVersion, batchNumber: batchNumber)
    }
}
