import Logging

extension FDB.Database {
    /// Runs given closure within a transaction and commits it, retrying on retryable errors.
    ///
    /// Retries follow FoundationDB semantics: on an error the transaction is passed to
    /// ``FDB/Transaction/onError(_:)``, which decides whether the error is retryable, applies a backoff delay and
    /// resets the transaction. Retrying stops when the error is not retryable or the retry limit is reached
    /// (see `transactionRetryLimit` in ``init(clusterFile:transactionRetryLimit:transactionTimeout:logger:)``).
    ///
    /// The closure may be executed several times, so it must be idempotent (apart from the transaction itself).
    /// Errors thrown by the closure which are not ``FDB/Error``s (or ``FDBErrorWrapper``s wrapping them, like
    /// ``FDB/RangeError``) are rethrown as is, without retrying.
    ///
    /// The transaction is lent to the closure and can't escape it.
    public func withTransaction<T>(_ body: (borrowing FDB.Transaction) async throws -> T) async throws -> T {
        try await self.run(versionstamp: false, body).result
    }

    /// Same as ``withTransaction(_:)``, but also returns the versionstamp of the committed transaction.
    ///
    /// Useful together with ``FDB/Transaction/set(versionstampedKey:value:)``
    /// to learn the actual versionstamp which was written.
    public func withVersionstampedTransaction<T>(
        _ body: (borrowing FDB.Transaction) async throws -> T
    ) async throws -> (result: T, versionstamp: FDB.Versionstamp) {
        let (result, versionstamp) = try await self.run(versionstamp: true, body)
        return (result, versionstamp!)
    }

    private func run<T>(
        versionstamp: Bool,
        _ body: (borrowing FDB.Transaction) async throws -> T
    ) async throws -> (result: T, versionstamp: FDB.Versionstamp?) {
        let transaction = try self.makeTransaction()
        var attempt = 0

        while true {
            do {
                let result = try await body(transaction)
                let versionstampFuture = versionstamp ? transaction.getVersionstamp() : nil
                try await transaction.commit().value()
                return (result, try await versionstampFuture?.value())
            } catch {
                guard
                    let error = (error as? FDB.Error) ?? (error as? any FDBErrorWrapper)?.underlyingFDBError,
                    error.isNative
                else {
                    throw error
                }
                attempt += 1
                self.logger.debug("Transaction failed with \(error), attempt \(attempt)")
                // Throws if the error is not retryable or the retry limit is reached
                try await transaction.onError(error).value()
            }
        }
    }

    // MARK: - Single-operation helpers

    /// Reads a value of given key in a separate transaction
    public func get(key: some FDBKey, snapshot: Bool = false) async throws -> Bytes? {
        try await self.withTransaction { tr in
            try await tr.get(key: key, snapshot: snapshot).value()
        }
    }

    /// Reads all key-value pairs in given range in a separate transaction
    public func getAll(
        _ range: FDB.KeyRange,
        limit: Int = 0,
        snapshot: Bool = false,
        reverse: Bool = false
    ) async throws -> [FDB.KeyValue] {
        try await self.withTransaction { tr in
            try await tr.getAll(range, limit: limit, snapshot: snapshot, reverse: reverse)
        }
    }

    /// Sets the value of given key in a separate transaction
    public func set(key: some FDBKey, value: Bytes) async throws {
        try await self.withTransaction { tr in
            tr.set(key: key, value: value)
        }
    }

    /// Clears given key in a separate transaction
    public func clear(key: some FDBKey) async throws {
        try await self.withTransaction { tr in
            tr.clear(key: key)
        }
    }

    /// Clears all keys in given range in a separate transaction
    public func clear(range: FDB.KeyRange) async throws {
        try await self.withTransaction { tr in
            tr.clear(range: range)
        }
    }

    /// Performs an atomic operation in a separate transaction
    public func atomic(_ op: FDB.MutationType, key: some FDBKey, value: Bytes) async throws {
        try await self.withTransaction { tr in
            tr.atomic(op, key: key, value: value)
        }
    }

    /// Atomically adds given number to the little-endian 64-bit integer stored at given key.
    ///
    /// Doesn't read the key, so it never conflicts with other increments.
    public func increment(key: some FDBKey, by value: Int64 = 1) async throws {
        try await self.atomic(.add, key: key, value: withUnsafeBytes(of: value.littleEndian) { Bytes($0) })
    }
}
