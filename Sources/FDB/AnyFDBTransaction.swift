public protocol AnyFDBTransaction: Sendable {
    // MARK: - Sync methods

    /// Destroys current transaction. It becomes unusable after this.
    func destroy()

    /// Cancels the transaction. All pending or future uses of the transaction will return
    /// a `transaction_cancelled` error. The transaction can be used again after it is `reset`.
    func cancel()

    /// Reset transaction to its initial state.
    /// This is similar to creating a new transaction after destroying previous one.
    func reset()

    /// Clears given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    func clear(key: AnyFDBKey)

    /// Clears keys in given range in FDB cluster
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    func clear(begin: AnyFDBKey, end: AnyFDBKey)

    /// Clears keys in given range in FDB cluster
    ///
    /// - parameters:
    ///   - range: Range key
    func clear(range: FDB.RangeKey)

    /// Peforms an atomic operation in FDB cluster on given key with given value bytes
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes)

    /// Peforms an atomic operation in FDB cluster on given key with given generic value
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T)

    /// Sets the snapshot read version used by a transaction
    ///
    /// This is not needed in simple cases. If the given version is too old, subsequent reads will fail
    /// with `error_code_past_version`; if it is too new, subsequent reads may be delayed indefinitely and/or fail
    /// with `error_code_future_version`. If any of `fdb_transaction_get_*()` have been called
    /// on this transaction already, the result is undefined.
    func setReadVersion(version: Int64)

    // MARK: - Async methods

    /// Commits current transaction
    func commit() async throws

    /// Sets bytes to given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Bytes value
    func set(key: AnyFDBKey, value: Bytes)

    /// Sets bytes to given versionstamped key in FDB cluster. If versionstampedKey does not contain
    /// an incomplete version stamp, this method will throw an error. The actual version stamp used
    /// may be retrieved by calling `getVersionstamp()` on the transaction.
    ///
    /// - parameters:
    ///   - versionstampedKey: FDB key containing an incomplete Versionstamp
    ///   - value: Bytes value
    ///
    /// - Throws: Throws FDB.Error.missingIncompleteVersionstamp if a version stamp cannot be found
    func set(versionstampedKey: AnyFDBKey, value: Bytes) throws

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///
    /// - returns: Bytes result or `nil` if no key
    func get(key: AnyFDBKey, snapshot: Bool) async throws -> Bytes?

    /// Returns a range of keys and their respective values in given key range
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    ///   - beginEqual: Should begin key also include exact key value
    ///   - beginOffset: Begin key offset
    ///   - endEqual: Should end key also include exact key value
    ///   - endOffset: End key offset
    ///   - limit: Limit returned key-value pairs (only relevant when `mode` is `.exact`)
    ///   - targetBytes: If non-zero, indicates a soft cap on the combined number of bytes of keys and values to return
    ///   - mode: The manner in which rows are returned (see `FDB.StreamingMode` docs)
    ///   - iteration: If `mode` is `.iterator`, this arg represent current read iteration (should start from 1)
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - reverse: If `true`, key-value pairs will be returned in reverse lexicographical order
    ///
    /// - returns: `(FDB.KeyValuesResult, AnyFDBTransaction)`
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
    ) async throws -> FDB.KeyValuesResult

    /// Returns a range of keys and their respective values in given key range
    ///
    /// - parameters:
    ///   - range: Range key
    ///   - beginEqual: Should begin key also include exact key value
    ///   - beginOffset: Begin key offset
    ///   - endEqual: Should end key also include exact key value
    ///   - endOffset: End key offset
    ///   - limit: Limit returned key-value pairs (only relevant when `mode` is `.exact`)
    ///   - targetBytes: If non-zero, indicates a soft cap on the combined number of bytes of keys and values to return
    ///   - mode: The manner in which rows are returned (see `FDB.StreamingMode` docs)
    ///   - iteration: If `mode` is `.iterator`, this arg represent current read iteration (should start from 1)
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - reverse: If `true`, key-value pairs will be returned in reverse lexicographical order
    ///
    /// - returns: `(FDB.KeyValuesResult, AnyFDBTransaction)`
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
    ) async throws -> FDB.KeyValuesResult

    /// Returns transaction snapshot read version
    ///
    /// - returns: Read version as Int64
    func getReadVersion() async throws -> Int64

    /// Commits transaction and returns versionstamp which was used by any versionstamp operations
    /// in this transaction. Note that this method must commit the transaction in order to wait for the
    /// versionstamp to become available.
    ///
    /// - returns: Version stamp as FDB.Versionstamp
    func getVersionstamp() async throws -> FDB.Versionstamp
}

/// Sync methods
public extension AnyFDBTransaction {
    /// Sets bytes to given versionstamped key in FDB cluster. If versionstampedKey does not contain
    /// an incomplete version stamp, this method will throw an error. The actual version stamp used
    /// may be retrieved by calling `getVersionstamp()` on the transaction.
    ///
    /// - parameters:
    ///   - versionstampedKey: FDB key containing an incomplete Versionstamp
    ///   - value: Bytes value
    ///
    /// - Throws: Throws FDB.Error.missingIncompleteVersionstamp if a version stamp cannot be found
    func set(versionstampedKey: AnyFDBKey, value: Bytes) throws {
        try self.set(versionstampedKey: versionstampedKey, value: value)
    }

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///
    /// - returns: Bytes result or `nil` if no key
    func get(key: AnyFDBKey, snapshot: Bool = false) async throws -> Bytes? {
        try await self.get(key: key, snapshot: snapshot)
    }

    /// Returns a range of keys and their respective values in given key range
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    ///   - beginEqual: Should begin key also include exact key value
    ///   - beginOffset: Begin key offset
    ///   - endEqual: Should end key also include exact key value
    ///   - endOffset: End key offset
    ///   - limit: Limit returned key-value pairs (only relevant when `mode` is `.exact`)
    ///   - targetBytes: If non-zero, indicates a soft cap on the combined number of bytes of keys and values to return
    ///   - mode: The manner in which rows are returned (see `FDB.StreamingMode` docs)
    ///   - iteration: If `mode` is `.iterator`, this arg represent current read iteration (should start from 1)
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - reverse: If `true`, key-value pairs will be returned in reverse lexicographical order
    ///
    /// - returns: `(FDB.KeyValuesResult, AnyFDBTransaction)`
    func get(
        begin: AnyFDBKey,
        end: AnyFDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .wantAll,
        iteration: Int32 = 1,
        snapshot: Bool = false,
        reverse: Bool = false
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
        )
    }

    /// Returns a range of keys and their respective values in given key range
    ///
    /// - parameters:
    ///   - range: Range key
    ///   - beginEqual: Should begin key also include exact key value
    ///   - beginOffset: Begin key offset
    ///   - endEqual: Should end key also include exact key value
    ///   - endOffset: End key offset
    ///   - limit: Limit returned key-value pairs (only relevant when `mode` is `.exact`)
    ///   - targetBytes: If non-zero, indicates a soft cap on the combined number of bytes of keys and values to return
    ///   - mode: The manner in which rows are returned (see `FDB.StreamingMode` docs)
    ///   - iteration: If `mode` is `.iterator`, this arg represent current read iteration (should start from 1)
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - reverse: If `true`, key-value pairs will be returned in reverse lexicographical order
    ///
    /// - returns: `(FDB.KeyValuesResult, AnyFDBTransaction)`
    func get(
        range: FDB.RangeKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .wantAll,
        iteration: Int32 = 1,
        snapshot: Bool = false,
        reverse: Bool = false
    ) async throws -> FDB.KeyValuesResult {
        try await self.get(
            range: range,
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
