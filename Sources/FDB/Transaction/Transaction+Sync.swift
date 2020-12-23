import CFDB

public extension FDB.Transaction {
    func commit() async throws {
        let future: FDB.Future = await try self.commit().ready()
        let commitError = fdb_future_get_error(future.pointer)
        guard commitError == 0 else {
            let retryFuture: FDB.Future = await try fdb_transaction_on_error(self.pointer, commitError).futureReady()
            try fdb_future_get_error(retryFuture.pointer).orThrow()
            throw FDB.Error.transactionRetry(transaction: self)
        }
    }

    func set(key: AnyFDBKey, value: Bytes, commit: Bool) async throws {
        self.set(key: key, value: value)

        if commit {
            await try self.commit()
        }
    }
    
    func set(versionstampedKey: AnyFDBKey, value: Bytes, commit: Bool) async throws {
        var serializedKey = versionstampedKey.asFDBKey()
        let offset = try FDB.Tuple.offsetOfFirstIncompleteVersionstamp(from: serializedKey)
        serializedKey.append(contentsOf: getBytes(offset.littleEndian))
            
        await try self.atomic(.setVersionstampedKey, key: serializedKey, value: value, commit: commit) as Void
    }

    func get(key: AnyFDBKey, snapshot: Bool, commit: Bool) async throws -> Bytes? {
        let result: Bytes? = await try self.get(key: key, snapshot: snapshot).bytes()

        if commit {
            await try self.commit()
        }

        return result
    }

    func get(key: AnyFDBKey) async throws -> Bytes? {
        return await try self.get(key: key, snapshot: false, commit: false)
    }

    func get(range: FDB.RangeKey, snapshot: Bool, commit: Bool) async throws -> FDB.KeyValuesResult {
        return await try self.get(
            range: range,
            beginEqual: true,
            beginOffset: 0,
            endEqual: true,
            endOffset: 0,
            limit: 0,
            targetBytes: 0,
            mode: .wantAll,
            iteration: 0,
            snapshot: snapshot,
            reverse: false,
            commit: commit
        )
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
    ) async throws -> FDB.KeyValuesResult {
        let result = await try self.get(
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
        ).keyValues()

        if commit {
            await try self.commit()
        }

        return result
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
    ) async throws -> FDB.KeyValuesResult {
        let result: FDB.KeyValuesResult = await try self.get(
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
        ).keyValues()

        if commit {
            await try self.commit()
        }

        return result
    }

    func clear(key: AnyFDBKey, commit: Bool) async throws {
        self.clear(key: key) as Void

        if commit {
            await try self.commit()
        }
    }

    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool) async throws {
        self.clear(begin: begin, end: end)

        if commit {
            await try self.commit()
        }
    }

    func clear(range: FDB.RangeKey, commit: Bool) async throws {
        await try self.clear(begin: range.begin, end: range.end, commit: commit) as Void
    }

    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes, commit: Bool) async throws {
        self.atomic(op, key: key, value: value)

        if commit {
            await try self.commit()
        }
    }

    func atomic<T>(_ op: FDB.MutationType, key: AnyFDBKey, value: T, commit: Bool) async throws {
        self.atomic(op, key: key, value: getBytes(value))

        if commit {
            await try self.commit()
        }
    }

    func getReadVersion() async throws -> Int64 {
        return await try self.getReadVersion().int64()
    }

    func getVersionstamp() async throws -> FDB.Versionstamp {
        let future: FDB.Future = self.getVersionstamp()

        await try self.commit()

        let bytes = await try future.keyBytes()

        guard bytes.count == 10 else {
            self.log("[getVersionstamp] Bytes that do not represent a versionstamp were returned: \(String(describing: bytes))", level: .error)
            throw FDB.Error.invalidVersionstamp
        }

        let transactionCommitVersion = try! UInt64(bigEndian: Bytes(bytes[0..<8]).cast())
        let batchNumber = try! UInt16(bigEndian: Bytes(bytes[8..<10]).cast())

        return FDB.Versionstamp(transactionCommitVersion: transactionCommitVersion, batchNumber: batchNumber)
    }

//    internal func _get(key: AnyFDBKey) async throws -> Bytes? {
//        try self.get(key: key, snapshot: false).wait()
//    }
}
