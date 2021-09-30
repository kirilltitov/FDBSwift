public extension FDB {
    func set(key: AnyFDBKey, value: Bytes) async throws {
        try await self.withTransaction {
            $0.set(key: key, value: value)
            try await $0.commit()
        }
    }

    func clear(key: AnyFDBKey) async throws {
        try await self.withTransaction {
            $0.clear(key: key)
            try await $0.commit()
        }
    }

    func clear(begin: AnyFDBKey, end: AnyFDBKey) async throws {
        try await self.withTransaction {
            $0.clear(begin: begin, end: end)
            try await $0.commit()
        }
    }

    func clear(range: FDB.RangeKey) async throws {
        try await self.clear(begin: range.begin, end: range.end)
    }

    func clear(subspace: Subspace) async throws {
        try await self.clear(range: subspace.range)
    }

    func get(key: AnyFDBKey, snapshot: Bool) async throws -> Bytes? {
        try await self.withTransaction {
            let result = try await $0.get(key: key, snapshot: snapshot)
            try await $0.commit()
            return result
        }
    }

    func get(subspace: Subspace, snapshot: Bool) async throws -> FDB.KeyValuesResult {
        try await self.withTransaction {
            let result = try await $0.get(range: subspace.range, snapshot: snapshot)
            try await $0.commit()
            return result
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
    ) async throws -> FDB.KeyValuesResult {
        try await self.withTransaction {
            let result = try await $0.get(
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
            try await $0.commit()
            return result
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
    ) async throws -> FDB.KeyValuesResult {
        try await self.get(
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

    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes) async throws {
        try await self.withTransaction {
            $0.atomic(op, key: key, value: value)
            try await $0.commit()
        }
    }

    func atomic<T: SignedInteger>(_ op: FDB.MutationType, key: AnyFDBKey, value: T) async throws {
        try await self.atomic(op, key: key, value: getBytes(value))
    }

    @discardableResult
    func increment(key: AnyFDBKey, value: Int64) async throws -> Int64 {
        try await self.withTransaction { transaction in
            transaction.atomic(.add, key: key, value: getBytes(value))

            guard let bytes: Bytes = try await transaction.get(key: key) else {
                throw FDB.Error.unexpectedError("Couldn't get key '\(key)' after increment")
            }

            try await transaction.commit()

            return try bytes.cast()
        }
    }

    @discardableResult
    func decrement(key: AnyFDBKey, value: Int64) async throws -> Int64 {
        try await self.increment(key: key, value: -value)
    }
}
