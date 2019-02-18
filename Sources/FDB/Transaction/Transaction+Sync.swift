import CFDB

public extension Transaction {
    public func commitSync() throws {
        let future: Future<Void> = try self.commit().wait()
        let commitError = fdb_future_get_error(future.pointer)
        guard commitError == 0 else {
            let retryFuture: Future<Void> = try fdb_transaction_on_error(self.pointer, commitError).waitForFuture()
            try fdb_future_get_error(retryFuture.pointer).orThrow()
            throw FDB.Error.transactionRetry
        }
    }

    public func set(key: FDBKey, value: Bytes, commit: Bool = false) throws {
        self.set(key: key, value: value)
        if commit {
            try self.commitSync()
        }
    }

    public func get(key: FDBKey, snapshot: Int32 = 0, commit: Bool = false) throws -> Bytes? {
        let result = try self.get(key: key, snapshot: snapshot).wait()
        if commit {
            try self.commitSync()
        }
        return result
    }

    public func get(
        begin: FDBKey,
        end: FDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .wantAll,
        iteration: Int32 = 1,
        snapshot: Int32 = 0,
        reverse: Bool = false,
        commit: Bool = false
    ) throws -> KeyValuesResult {
        let future: Future<KeyValuesResult> = try self.get(
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

    public func get(
        range: RangeFDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .wantAll,
        iteration: Int32 = 1,
        snapshot: Int32 = 0,
        reverse: Bool = false,
        commit: Bool = false
    ) throws -> KeyValuesResult {
        let future: Future<KeyValuesResult> = self.get(
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

    public func clear(key: FDBKey, commit: Bool = false) throws {
        self.clear(key: key)
        if commit {
            try self.commitSync()
        }
    }

    public func clear(begin: FDBKey, end: FDBKey, commit: Bool = false) throws {
        self.clear(begin: begin, end: end)
        if commit {
            try self.commitSync()
        }
    }

    public func clear(range: RangeFDBKey, commit: Bool = false) throws {
        try self.clear(begin: range.begin, end: range.end, commit: commit) as Void
    }

    public func atomic(_ op: FDB.MutationType, key: FDBKey, value: Bytes, commit: Bool = false) throws {
        self.atomic(op, key: key, value: value)
        if commit {
            try self.commitSync()
        }
    }

    public func atomic<T>(_ op: FDB.MutationType, key: FDBKey, value: T, commit: Bool = false) throws {
        self.atomic(op, key: key, value: getBytes(value))
        if commit {
            try self.commitSync()
        }
    }
}
