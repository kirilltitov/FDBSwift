import NIO

public protocol AnyFDBTransaction {
    func destroy()
    func cancel()
    func reset()
    func clear(key: AnyFDBKey)
    func clear(begin: AnyFDBKey, end: AnyFDBKey)
    func clear(range: FDB.RangeKey)
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes)
    func setReadVersion(version: Int64)

    /// NIO methods
    func commit() -> EventLoopFuture<Void>
    func set(key: AnyFDBKey, value: Bytes, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>
    func get(key: AnyFDBKey, snapshot: Bool, commit: Bool) -> EventLoopFuture<Bytes?>
    func get(key: AnyFDBKey, snapshot: Bool, commit: Bool) -> EventLoopFuture<(Bytes?, AnyFDBTransaction)>
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
    func clear(key: AnyFDBKey, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>
    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>
    func clear(range: FDB.RangeKey, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>
    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T, commit: Bool) -> EventLoopFuture<AnyFDBTransaction>
    func setOption(_ option: FDB.Transaction.Option) -> EventLoopFuture<AnyFDBTransaction>
    func getReadVersion() -> EventLoopFuture<Int64>

    /// Sync methods
    func commitSync() throws
    func set(key: AnyFDBKey, value: Bytes, commit: Bool) throws
    func get(key: AnyFDBKey, snapshot: Bool, commit: Bool) throws -> Bytes?
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
    func clear(key: AnyFDBKey, commit: Bool) throws
    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool) throws
    func clear(range: FDB.RangeKey, commit: Bool) throws
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes, commit: Bool) throws
    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T, commit: Bool) throws
    func getReadVersion() throws -> Int64
}

/// Sync methods
public extension AnyFDBTransaction {
    func set(key: AnyFDBKey, value: Bytes, commit: Bool = false) throws {
        try self.set(key: key, value: value, commit: commit) as Void
    }

    func get(key: AnyFDBKey, snapshot: Bool = false, commit: Bool = false) throws -> Bytes? {
        return try self.get(key: key, snapshot: snapshot, commit: commit)
    }

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

    func clear(key: AnyFDBKey, commit: Bool = false) throws {
        try self.clear(key: key, commit: commit) as Void
    }

    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool = false) throws {
        try self.clear(begin: begin, end: end, commit: commit) as Void
    }

    func clear(range: FDB.RangeKey, commit: Bool = false) throws {
        try self.clear(range: range, commit: commit) as Void
    }

    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes, commit: Bool = false) throws {
        try self.atomic(op, key: key, value: value, commit: commit) as Void
    }

    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T, commit: Bool = false) throws {
        try self.atomic(op, key: key, value: value, commit: commit) as Void
    }

    /// NIO methods
    func set(key: AnyFDBKey, value: Bytes, commit: Bool = false) -> EventLoopFuture<AnyFDBTransaction> {
        return self.set(key: key, value: value, commit: commit)
    }

    func get(key: AnyFDBKey, snapshot: Bool = false, commit: Bool = false) -> EventLoopFuture<Bytes?> {
        return self.get(key: key, snapshot: snapshot, commit: commit)
    }

    func get(
        key: AnyFDBKey,
        snapshot: Bool = false,
        commit: Bool = false
    ) -> EventLoopFuture<(Bytes?, AnyFDBTransaction)> {
        return self.get(key: key, snapshot: snapshot, commit: commit)
    }

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

    func clear(key: AnyFDBKey, commit: Bool = false) -> EventLoopFuture<AnyFDBTransaction> {
        return self.clear(key: key, commit: commit)
    }

    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool = false) -> EventLoopFuture<AnyFDBTransaction> {
        return self.clear(begin: begin, end: end, commit: commit)
    }

    func clear(range: FDB.RangeKey, commit: Bool = false) -> EventLoopFuture<AnyFDBTransaction> {
        return self.clear(range: range, commit: commit)
    }

    func atomic(
        _ op: FDB.MutationType,
        key: AnyFDBKey,
        value: Bytes,
        commit: Bool = false
    ) -> EventLoopFuture<AnyFDBTransaction> {
        return self.atomic(op, key: key, value: value, commit: commit)
    }

    func atomic<T>(
        _ op: FDB.MutationType,
        key: AnyFDBKey,
        value: T,
        commit: Bool = false
    ) -> EventLoopFuture<AnyFDBTransaction> {
        return self.atomic(op, key: key, value: value, commit: commit)
    }
}
