import CFDB

public extension FDB.Transaction {
    func commitSync() throws {
        let future: FDB.Future = try self.commit().wait()
        let commitError = fdb_future_get_error(future.pointer)
        guard commitError == 0 else {
            let retryFuture: FDB.Future = try fdb_transaction_on_error(self.pointer, commitError).waitForFuture()
            try fdb_future_get_error(retryFuture.pointer).orThrow()
            throw FDB.Error.transactionRetry(transaction: self)
        }
    }

    func set(key: AnyFDBKey, value: Bytes, commit: Bool) throws {
        self.set(key: key, value: value)
        if commit {
            try self.commitSync()
        }
    }

    func get(key: AnyFDBKey, snapshot: Bool, commit: Bool) throws -> Bytes? {
        let result: Bytes? = try self.get(key: key, snapshot: snapshot).wait()
        if commit {
            try self.commitSync()
        }
        return result
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

    func clear(key: AnyFDBKey, commit: Bool) throws {
        self.clear(key: key)
        if commit {
            try self.commitSync()
        }
    }

    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool) throws {
        self.clear(begin: begin, end: end)
        if commit {
            try self.commitSync()
        }
    }

    func clear(range: FDB.RangeKey, commit: Bool) throws {
        try self.clear(begin: range.begin, end: range.end, commit: commit) as Void
    }

    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes, commit: Bool) throws {
        self.atomic(op, key: key, value: value)
        if commit {
            try self.commitSync()
        }
    }

    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T, commit: Bool) throws {
        self.atomic(op, key: key, value: getBytes(value))
        if commit {
            try self.commitSync()
        }
    }

    func getReadVersion() throws -> Int64 {
        return try self.getReadVersion().wait()
    }
}
