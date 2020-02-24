public extension FDB {
    func set(key: AnyFDBKey, value: Bytes) throws {
        try self.withTransaction {
            try $0.set(key: key, value: value, commit: true) as Void
        }
    }

    func setSync(key: AnyFDBKey, value: Bytes) throws {
        try self.set(key: key, value: value) as Void
    }

    func clear(key: AnyFDBKey) throws {
        try self.withTransaction {
            try $0.clear(key: key, commit: true) as Void
        }
    }

    func clearSync(key: AnyFDBKey) throws {
        try self.clear(key: key) as Void
    }

    func clear(begin: AnyFDBKey, end: AnyFDBKey) throws {
        try self.withTransaction {
            try $0.clear(begin: begin, end: end, commit: true) as Void
        }
    }

    func clearSync(begin: AnyFDBKey, end: AnyFDBKey) throws {
        try self.clear(begin: begin, end: end) as Void
    }

    func clear(range: FDB.RangeKey) throws {
        return try self.clear(begin: range.begin, end: range.end)
    }

    func clear(subspace: Subspace) throws {
        return try self.clear(range: subspace.range)
    }

    func get(key: AnyFDBKey, snapshot: Bool) throws -> Bytes? {
        return try self.withTransaction {
            try $0.get(key: key, snapshot: snapshot, commit: true)
        }
    }

    func get(subspace: Subspace, snapshot: Bool) throws -> KeyValuesResult {
        return try self.withTransaction {
            try $0.get(range: subspace.range, snapshot: snapshot)
        }
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

    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes) throws {
        try self.withTransaction {
            try $0.atomic(op, key: key, value: value, commit: true) as Void
        }
    }

    func atomic<T: SignedInteger>(_ op: FDB.MutationType, key: AnyFDBKey, value: T) throws {
        try self.atomic(op, key: key, value: getBytes(value))
    }

    @discardableResult
    func increment(key: AnyFDBKey, value: Int64) throws -> Int64 {
        return try self.withTransaction { transaction in
            try transaction.atomic(.add, key: key, value: getBytes(value), commit: false) as Void

            guard let bytes: Bytes = try transaction.get(key: key) else {
                throw FDB.Error.unexpectedError("Couldn't get key '\(key)' after increment")
            }

            try transaction.commitSync()

            return try bytes.cast()
        }
    }

    @discardableResult
    func decrement(key: AnyFDBKey, value: Int64) throws -> Int64 {
        return try self.increment(key: key, value: -value)
    }
}
