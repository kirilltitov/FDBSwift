public extension FDB {
    func set(key: AnyFDBKey, value: Bytes) async throws {
        await try self.withTransaction {
            await try $0.set(key: key, value: value, commit: true) as Void
        }
    }

    func clear(key: AnyFDBKey) async throws {
        await try self.withTransaction {
            await try $0.clear(key: key, commit: true) as Void
        }
    }

    func clear(begin: AnyFDBKey, end: AnyFDBKey) async throws {
        await try self.withTransaction {
            await try $0.clear(begin: begin, end: end, commit: true) as Void
        }
    }

    func clear(range: FDB.RangeKey) async throws {
        await try self.clear(begin: range.begin, end: range.end)
    }

    func clear(subspace: Subspace) async throws {
        await try self.clear(range: subspace.range)
    }

    func get(key: AnyFDBKey, snapshot: Bool) async throws -> Bytes? {
        return await try self.withTransaction {
            await try $0.get(key: key, snapshot: snapshot, commit: true)
        }
    }

    func get(subspace: Subspace, snapshot: Bool) async throws -> FDB.KeyValuesResult {
        return await try self.withTransaction {
            return await try $0.get(range: subspace.range, snapshot: snapshot, commit: true)
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
        return await try self.withTransaction {
            await try $0.get(
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
    ) async throws -> FDB.KeyValuesResult {
        return await try self.get(
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
        await try self.withTransaction {
            await try $0.atomic(op, key: key, value: value, commit: true) as Void
        }
    }

    func atomic<T: SignedInteger>(_ op: FDB.MutationType, key: AnyFDBKey, value: T) async throws {
        await try self.atomic(op, key: key, value: getBytes(value))
    }

    @discardableResult
    func increment(key: AnyFDBKey, value: Int64) async throws -> Int64 {
        return await try self.withTransaction { transaction in
            await try transaction.atomic(.add, key: key, value: getBytes(value), commit: false) as Void

            guard let bytes: Bytes = await try transaction.get(key: key) else {
                throw FDB.Error.unexpectedError("Couldn't get key '\(key)' after increment")
            }

            await try transaction.commit()

            return try bytes.cast()
        }
    }

    @discardableResult
    func decrement(key: AnyFDBKey, value: Int64) async throws -> Int64 {
        return await try self.increment(key: key, value: -value)
    }
}
