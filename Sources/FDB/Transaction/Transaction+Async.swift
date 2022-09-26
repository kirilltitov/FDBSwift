import CFDB

public extension FDB.Transaction {
    internal func resolvedWithRetryableErrorCheck(future: FDB.Future) async throws {
        try await future.resolved()

        let errno = future.errno
        guard errno == 0 else {
            let retryFuture = fdb_transaction_on_error(self.pointer, errno).asFuture()
            try await retryFuture.resolvedThrowing()

            /// The fact that future above didn't throw means that the transaction can be retried.
            /// Otherwise the transaction must be considered dead.
            throw FDB.Error.transactionRetry
        }
    }

    func commit() async throws {
        let future: FDB.Future = self.commit()

        try await self.resolvedWithRetryableErrorCheck(future: future)
    }

    func set(versionstampedKey: any FDBKey, value: Bytes) throws {
        var serializedKey = versionstampedKey.asFDBKey()
        let offset = try FDB.Tuple.offsetOfFirstIncompleteVersionstamp(from: serializedKey)
        serializedKey.append(contentsOf: getBytes(offset.littleEndian))

        self.atomic(.setVersionstampedKey, key: serializedKey, value: value)
    }

    func get(key: any FDBKey, snapshot: Bool) async throws -> Bytes? {
        let future: FDB.Future = self.get(key: key, snapshot: snapshot)

        try await self.resolvedWithRetryableErrorCheck(future: future)

        return try await future.bytes()
    }

    func get(key: any FDBKey) async throws -> Bytes? {
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
        begin: any FDBKey,
        end: any FDBKey,
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
        let future: FDB.Future = self.get(
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
        )

        try await self.resolvedWithRetryableErrorCheck(future: future)

        return try await future.keyValues()
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
        let future: FDB.Future = self.get(
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

        try await self.resolvedWithRetryableErrorCheck(future: future)

        return try await future.keyValues()
    }

    func atomic<T>(_ op: FDB.MutationType, key: any FDBKey, value: T) {
        self.atomic(op, key: key, value: getBytes(value))
    }

    func getReadVersion() async throws -> Int64 {
        let future: FDB.Future = self.getReadVersion()

        try await self.resolvedWithRetryableErrorCheck(future: future)

        return try await future.int64()
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
