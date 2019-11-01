import NIO

public protocol AnyFDBTransaction {
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

    /// Sets the snapshot read version used by a transaction
    ///
    /// This is not needed in simple cases. If the given version is too old, subsequent reads will fail
    /// with `error_code_past_version`; if it is too new, subsequent reads may be delayed indefinitely and/or fail
    /// with `error_code_future_version`. If any of `fdb_transaction_get_*()` have been called
    /// on this transaction already, the result is undefined.
    func setReadVersion(version: Int64)

    /// NIO methods

    /// Commits current transaction
    ///
    /// - returns: EventLoopFuture with future Void value
    func commit() -> EventLoopFuture<Void>

    /// Sets bytes to given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Bytes value
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func set(key: AnyFDBKey, value: Bytes, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `Bytes?` tuple value
    func get(key: AnyFDBKey, snapshot: Bool, commit: Bool) -> EventLoopFuture<Bytes?>

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(Bytes?, AnyFDBTransaction)` tuple value
    func get(key: AnyFDBKey, snapshot: Bool, commit: Bool) -> EventLoopFuture<(Bytes?, AnyFDBTransaction)>

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
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `FDB.KeyValuesResult` tuple value
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
        reverse: Bool,
        commit: Bool
    ) -> EventLoopFuture<FDB.KeyValuesResult>

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
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(FDB.KeyValuesResult, AnyFDBTransaction)` tuple value
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
        reverse: Bool,
        commit: Bool
    ) -> EventLoopFuture<(FDB.KeyValuesResult, AnyFDBTransaction)>

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
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(FDB.KeyValuesResult, AnyFDBTransaction)` tuple value
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
        reverse: Bool,
        commit: Bool
    ) -> EventLoopFuture<FDB.KeyValuesResult>

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
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(FDB.KeyValuesResult, AnyFDBTransaction)` tuple value
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
        reverse: Bool,
        commit: Bool
    ) -> EventLoopFuture<(FDB.KeyValuesResult, AnyFDBTransaction)>

    /// Clears given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func clear(key: AnyFDBKey, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>

    /// Clears keys in given range in FDB cluster
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>

    /// Clears keys in given range in FDB cluster
    ///
    /// - parameters:
    ///   - range: Range key
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func clear(range: FDB.RangeKey, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>

    /// Peforms an atomic operation in FDB cluster on given key with given value bytes
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>

    /// Peforms an atomic operation in FDB cluster on given key with given generic value
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>

    /// Sets a transaction option to current transaction
    ///
    /// - parameters:
    ///   - option: Transaction option
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func setOption(_ option: FDB.Transaction.Option) -> EventLoopFuture<AnyFDBTransaction>

    /// Returns transaction snapshot read version
    ///
    /// - returns: EventLoopFuture with future Int64 value
    func getReadVersion() -> EventLoopFuture<Int64>

    /// Sync methods

    /// Commits current transaction
    ///
    /// This function will block current thread during execution
    func commitSync() throws

    /// Sets bytes to given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Bytes value
    ///   - commit: Whether to commit this transaction after action or not
    func set(key: AnyFDBKey, value: Bytes, commit: Bool) throws

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: Bytes result or `nil` if no key
    func get(key: AnyFDBKey, snapshot: Bool, commit: Bool) throws -> Bytes?

    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
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
    ///   - commit: Whether to commit this transaction after action or not
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
        reverse: Bool,
        commit: Bool
    ) throws -> FDB.KeyValuesResult

    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
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
    ///   - commit: Whether to commit this transaction after action or not
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
        reverse: Bool,
        commit: Bool
    ) throws -> FDB.KeyValuesResult

    /// Clears given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - commit: Whether to commit this transaction after action or not
    func clear(key: AnyFDBKey, commit: Bool) throws

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    ///   - commit: Whether to commit this transaction after action or not
    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool) throws

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - range: Range key
    ///   - commit: Whether to commit this transaction after action or not
    func clear(range: FDB.RangeKey, commit: Bool) throws

    /// Peforms an atomic operation in FDB cluster on given key with given value bytes
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    ///   - commit: Whether to commit this transaction after action or not
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes, commit: Bool) throws

    /// Peforms an atomic operation in FDB cluster on given key with given generic value
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    ///   - commit: Whether to commit this transaction after action or not
    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T, commit: Bool) throws

    /// Returns transaction snapshot read version
    ///
    /// This function will block current thread during execution
    ///
    /// - returns: Read version as Int64
    func getReadVersion() throws -> Int64
}

/// Sync methods
public extension AnyFDBTransaction {
    /// Sets bytes to given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Bytes value
    ///   - commit: Whether to commit this transaction after action or not
    func set(key: AnyFDBKey, value: Bytes, commit: Bool = false) throws {
        try self.set(key: key, value: value, commit: commit) as Void
    }

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: Bytes result or `nil` if no key
    func get(key: AnyFDBKey, snapshot: Bool = false, commit: Bool = false) throws -> Bytes? {
        return try self.get(key: key, snapshot: snapshot, commit: commit)
    }

    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
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
    ///   - commit: Whether to commit this transaction after action or not
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
        reverse: Bool = false,
        commit: Bool = false
    ) throws -> FDB.KeyValuesResult {
        return try self.get(
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

    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
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
    ///   - commit: Whether to commit this transaction after action or not
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
        reverse: Bool = false,
        commit: Bool = false
    ) throws -> FDB.KeyValuesResult {
        return try self.get(
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
            reverse: reverse,
            commit: commit
        )
    }

    /// Clears given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - commit: Whether to commit this transaction after action or not
    func clear(key: AnyFDBKey, commit: Bool = false) throws {
        try self.clear(key: key, commit: commit) as Void
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    ///   - commit: Whether to commit this transaction after action or not
    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool = false) throws {
        try self.clear(begin: begin, end: end, commit: commit) as Void
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - range: Range key
    ///   - commit: Whether to commit this transaction after action or not
    func clear(range: FDB.RangeKey, commit: Bool = false) throws {
        try self.clear(range: range, commit: commit) as Void
    }

    /// Peforms an atomic operation in FDB cluster on given key with given value bytes
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    ///   - commit: Whether to commit this transaction after action or not
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes, commit: Bool = false) throws {
        try self.atomic(op, key: key, value: value, commit: commit) as Void
    }
    /// Peforms an atomic operation in FDB cluster on given key with given generic value
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    ///   - commit: Whether to commit this transaction after action or not
    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T, commit: Bool = false) throws {
        try self.atomic(op, key: key, value: value, commit: commit) as Void
    }

    /// Sets bytes to given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Bytes value
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func set(key: AnyFDBKey, value: Bytes, commit: Bool = false) -> EventLoopFuture<AnyFDBTransaction> {
        return self.set(key: key, value: value, commit: commit)
    }

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `Bytes?` tuple value
    func get(key: AnyFDBKey, snapshot: Bool = false, commit: Bool = false) -> EventLoopFuture<Bytes?> {
        return self.get(key: key, snapshot: snapshot, commit: commit)
    }

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(Bytes?, AnyFDBTransaction)` tuple value
    func get(
        key: AnyFDBKey,
        snapshot: Bool = false,
        commit: Bool = false
    ) -> EventLoopFuture<(Bytes?, AnyFDBTransaction)> {
        return self.get(key: key, snapshot: snapshot, commit: commit)
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
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `FDB.KeyValuesResult` tuple value
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
        reverse: Bool = false,
        commit: Bool = false
    ) -> EventLoopFuture<FDB.KeyValuesResult> {
        return self.get(
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
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(FDB.KeyValuesResult, AnyFDBTransaction)` tuple value
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
        reverse: Bool = false,
        commit: Bool = false
    ) -> EventLoopFuture<(FDB.KeyValuesResult, AnyFDBTransaction)> {
        return self.get(
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
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(FDB.KeyValuesResult, AnyFDBTransaction)` tuple value
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
        reverse: Bool = false,
        commit: Bool = false
    ) -> EventLoopFuture<FDB.KeyValuesResult> {
        return self.get(
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
            reverse: reverse,
            commit: commit
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
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(FDB.KeyValuesResult, AnyFDBTransaction)` tuple value
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
        reverse: Bool = false,
        commit: Bool = false
    ) -> EventLoopFuture<(FDB.KeyValuesResult, AnyFDBTransaction)> {
        return self.get(
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
            reverse: reverse,
            commit: commit
        )
    }

    /// Clears given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func clear(key: AnyFDBKey, commit: Bool = false) -> EventLoopFuture<AnyFDBTransaction> {
        return self.clear(key: key, commit: commit)
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool = false) -> EventLoopFuture<AnyFDBTransaction> {
        return self.clear(begin: begin, end: end, commit: commit)
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// - parameters:
    ///   - range: Range key
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func clear(range: FDB.RangeKey, commit: Bool = false) -> EventLoopFuture<AnyFDBTransaction> {
        return self.clear(range: range, commit: commit)
    }

    /// Peforms an atomic operation in FDB cluster on given key with given value bytes
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func atomic(
        _ op: FDB.MutationType,
        key: AnyFDBKey,
        value: Bytes,
        commit: Bool = false
    ) -> EventLoopFuture<AnyFDBTransaction> {
        return self.atomic(op, key: key, value: value, commit: commit)
    }

    /// Peforms an atomic operation in FDB cluster on given key with given generic value
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    func atomic<T>(
        _ op: FDB.MutationType,
        key: AnyFDBKey,
        value: T,
        commit: Bool = false
    ) -> EventLoopFuture<AnyFDBTransaction> {
        return self.atomic(op, key: key, value: value, commit: commit)
    }
}
