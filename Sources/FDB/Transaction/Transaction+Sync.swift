import CFDB

public extension FDB.Transaction {
    /// Commits current transaction
    ///
    /// This function will block current thread during execution
    func commitSync() throws {
        let future: FDB.Future = try self.commit().wait()
        let commitError = fdb_future_get_error(future.pointer)
        guard commitError == 0 else {
            let retryFuture: FDB.Future = try fdb_transaction_on_error(self.pointer, commitError).waitForFuture()
            try fdb_future_get_error(retryFuture.pointer).orThrow()
            throw FDB.Error.transactionRetry(transaction: self)
        }
    }

    /// Sets bytes to given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Bytes value
    ///   - commit: Whether to commit this transaction after action or not
    func set(key: AnyFDBKey, value: Bytes, commit: Bool) throws {
        self.set(key: key, value: value)
        if commit {
            try self.commitSync()
        }
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
    func get(key: AnyFDBKey, snapshot: Bool, commit: Bool) throws -> Bytes? {
        let result: Bytes? = try self.get(key: key, snapshot: snapshot).wait()
        if commit {
            try self.commitSync()
        }
        return result
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
    ) throws -> FDB.KeyValuesResult {
        let future: FDB.Future = try self.get(
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
        ).wait()
        if commit {
            try self.commitSync()
        }
        return try future.wait()
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
    ) throws -> FDB.KeyValuesResult {
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
        if commit {
            try self.commitSync()
        }
        return try future.wait()
    }

    /// Clears given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - commit: Whether to commit this transaction after action or not
    func clear(key: AnyFDBKey, commit: Bool) throws {
        self.clear(key: key)
        if commit {
            try self.commitSync()
        }
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    ///   - commit: Whether to commit this transaction after action or not
    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool) throws {
        self.clear(begin: begin, end: end)
        if commit {
            try self.commitSync()
        }
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - range: Range key
    ///   - commit: Whether to commit this transaction after action or not
    func clear(range: FDB.RangeKey, commit: Bool) throws {
        try self.clear(begin: range.begin, end: range.end, commit: commit) as Void
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
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes, commit: Bool) throws {
        self.atomic(op, key: key, value: value)
        if commit {
            try self.commitSync()
        }
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
    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T, commit: Bool) throws {
        self.atomic(op, key: key, value: getBytes(value))
        if commit {
            try self.commitSync()
        }
    }

    /// Returns transaction snapshot read version
    ///
    /// This function will block current thread during execution
    ///
    /// - returns: Read version as Int64
    func getReadVersion() throws -> Int64 {
        return try self.getReadVersion().wait()
    }
}
