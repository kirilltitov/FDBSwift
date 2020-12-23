public extension FDB {
    func set(key: AnyFDBKey, value: Bytes) async throws {
        await try self.withTransaction {
            $0.set(key: key, value: value)
            await try $0.commit()
        }
    }

    func clear(key: AnyFDBKey) async throws {
        await try self.withTransaction {
            $0.clear(key: key)
            await try $0.commit()
        }
    }

    func clear(begin: AnyFDBKey, end: AnyFDBKey) async throws {
        await try self.withTransaction {
            $0.clear(begin: begin, end: end)
            await try $0.commit()
        }
    }

    func clear(range: FDB.RangeKey) async throws {
        await try self.clear(begin: range.begin, end: range.end)
    }

    func clear(subspace: Subspace) async throws {
        await try self.clear(range: subspace.range)
    }

    func get(key: AnyFDBKey, snapshot: Bool) async throws -> Bytes? {
        await try self.withTransaction {
            let result = await try $0.get(key: key, snapshot: snapshot)
            await try $0.commit()
            return result
        }
    }

    func get(subspace: Subspace, snapshot: Bool) async throws -> FDB.KeyValuesResult {
        await try self.withTransaction {
            let result = await try $0.get(range: subspace.range, snapshot: snapshot)
            await try $0.commit()
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
        await try self.withTransaction {
            let result = await try $0.get(
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
            await try $0.commit()
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
        await try self.get(
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
            $0.atomic(op, key: key, value: value)
            await try $0.commit()
        }
    }

    func atomic<T: SignedInteger>(_ op: FDB.MutationType, key: AnyFDBKey, value: T) async throws {
        await try self.atomic(op, key: key, value: getBytes(value))
    }

    @discardableResult
    func increment(key: AnyFDBKey, value: Int64) async throws -> Int64 {
        await try self.withTransaction { transaction in
            transaction.atomic(.add, key: key, value: getBytes(value))

            guard let bytes: Bytes = await try transaction.get(key: key) else {
                throw FDB.Error.unexpectedError("Couldn't get key '\(key)' after increment")
            }

            await try transaction.commit()

            return try bytes.cast()
        }
    }

    @discardableResult
    func decrement(key: AnyFDBKey, value: Int64) async throws -> Int64 {
        await try self.increment(key: key, value: -value)
    }
}
