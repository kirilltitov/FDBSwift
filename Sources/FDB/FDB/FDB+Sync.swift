public extension FDB {
    /// Sets bytes to given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: bytes value
    func set(key: AnyFDBKey, value: Bytes) throws {
        try self.withTransaction {
            try $0.set(key: key, value: value, commit: true) as Void
        }
    }

    /// Sets bytes to given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: bytes value
    func setSync(key: AnyFDBKey, value: Bytes) throws {
        try self.set(key: key, value: value) as Void
    }

    /// Clears given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    func clear(key: AnyFDBKey) throws {
        try self.withTransaction {
            try $0.clear(key: key, commit: true) as Void
        }
    }

    /// Clears given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    func clearSync(key: AnyFDBKey) throws {
        try self.clear(key: key) as Void
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    func clear(begin: AnyFDBKey, end: AnyFDBKey) throws {
        try self.withTransaction {
            try $0.clear(begin: begin, end: end, commit: true) as Void
        }
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    func clearSync(begin: AnyFDBKey, end: AnyFDBKey) throws {
        try self.clear(begin: begin, end: end) as Void
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - range: Range key
    func clear(range: FDB.RangeKey) throws {
        return try self.clear(begin: range.begin, end: range.end)
    }

    /// Clears keys in given subspace in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - subspace: Subspace to clear
    func clear(subspace: Subspace) throws {
        return try self.clear(range: subspace.range)
    }

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(key: AnyFDBKey, snapshot: Bool) throws -> Bytes? {
        return try self.withTransaction {
            try $0.get(key: key, snapshot: snapshot, commit: true)
        }
    }

    /// Returns a range of keys and their respective values under given subspace
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - subspace: Subspace
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(subspace: Subspace, snapshot: Bool) throws -> KeyValuesResult {
        return try self.withTransaction {
            try $0.get(range: subspace.range, snapshot: snapshot)
        }
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
    ) throws -> FDB.KeyValuesResult {
        return try self.withTransaction {
            try $0.get(
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
                commit: true
            )
        }
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
    ) throws -> FDB.KeyValuesResult {
        return try self.get(
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
    }

    /// Peforms an atomic operation in FDB cluster on given key with given value bytes
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - op: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes) throws {
        try self.withTransaction {
            try $0.atomic(op, key: key, value: value, commit: true) as Void
        }
    }

    /// Peforms an atomic operation in FDB cluster on given key with given signed integer value
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - op: Atomic operation
    ///   - key: FDB key
    ///   - value: Integer
    func atomic<T: SignedInteger>(_ op: FDB.MutationType, key: AnyFDBKey, value: T) throws {
        try self.atomic(op, key: key, value: getBytes(value))
    }

    /// Peforms a quasi-atomic increment operation in FDB cluster on given key with given integer
    ///
    /// This function will block current thread during execution
    ///
    /// Warning: though this function uses atomic `.add` increment, immediate serializable read of incremented key
    /// negates all benefits of atomicity, and therefore it shouldn't be considered truly atomical. However, it still
    /// works, and it gives you guarantees that only you will get the incremented value. It may lead to increased
    /// read conflicts on high load (hence lower performance), and is only usable when generating serial integer IDs.
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Integer
    @discardableResult func increment(key: AnyFDBKey, value: Int64) throws -> Int64 {
        return try self.withTransaction { transaction in
            try transaction.atomic(.add, key: key, value: getBytes(value), commit: false) as Void

            guard let bytes: Bytes = try transaction.get(key: key) else {
                throw FDB.Error.unexpectedError("Couldn't get key '\(key)' after increment")
            }

            try transaction.commitSync()

            return try bytes.cast()
        }
    }

    /// Peforms a quasi-atomic decrement operation in FDB cluster on given key with given integer
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Integer
    @discardableResult func decrement(key: AnyFDBKey, value: Int64) throws -> Int64 {
        return try self.increment(key: key, value: -value)
    }
}
