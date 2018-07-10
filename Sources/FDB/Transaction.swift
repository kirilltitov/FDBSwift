import CFDB

public struct KeyValue {
    public let key: Bytes
    public let value: Bytes
}

public class Transaction {
    public var pointer: OpaquePointer!

    public init(_ pointer: OpaquePointer? = nil) {
        self.pointer = pointer
    }

    public class func begin(_ db: FDB.Database) throws -> Transaction {
        let transaction = Transaction()
        try fdb_database_create_transaction(db, &transaction.pointer).orThrow()
        return transaction
    }

    deinit {
        fdb_transaction_destroy(self.pointer)
    }

    public func commit() throws {
        let commitFuture = try fdb_transaction_commit(self.pointer).waitForFuture()
        let commitError = fdb_future_get_error(commitFuture.pointer)
        guard commitError == 0 else {
            let retryFuture = try fdb_transaction_on_error(self.pointer, commitError).waitForFuture()
            try fdb_future_get_error(retryFuture.pointer).orThrow()
            throw FDB.Error.TransactionRetry
        }
    }

    public func set(key: FDBKey, value: Bytes, commit: Bool = false) throws {
        fdb_transaction_set(self.pointer, key.asFDBKey(), key.asFDBKeyLength(), value, Int32(value.count))
        if commit {
            try self.commit()
        }
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
        mode: FDB.StreamingMode = .WantAll,
        iteration: Int32 = 1,
        snapshot: Int32 = 0,
        reverse: Bool = false,
        commit: Bool = false
    ) throws -> [KeyValue] {
        let future = try fdb_transaction_get_range(
            self.pointer,
            begin.asFDBKey(), begin.asFDBKeyLength(), beginEqual.int, beginOffset,
            end.asFDBKey(), end.asFDBKeyLength(), endEqual.int, endOffset,
            limit,
            targetBytes,
            FDBStreamingMode(mode.rawValue),
            iteration,
            snapshot,
            reverse.int
        ).waitForFuture()

        var outRawValues: UnsafePointer<FDBKeyValue>!
        var outCount: Int32 = 0
        var outMore: Int32 = 0

        try fdb_future_get_keyvalue_array(future.pointer, &outRawValues, &outCount, &outMore).orThrow()

        return outCount == 0 ? [] : outRawValues.unwrapPointee(count: outCount).map {
            return KeyValue(
                key: $0.key.getBytes(count: $0.key_length),
                value: $0.value.getBytes(count: $0.value_length)
            )
        }
    }

    public func get(
        range: RangeFDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .WantAll,
        iteration: Int32 = 1,
        snapshot: Int32 = 0,
        reverse: Bool = false,
        commit: Bool = false
    ) throws -> [KeyValue] {
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
            reverse: reverse,
            commit: commit
        )
    }

    public func get(key: FDBKey, snapshot: Int32 = 0, commit: Bool = false) throws -> Bytes? {
        let future = try fdb_transaction_get(
            self.pointer,
            key.asFDBKey(),
            key.asFDBKeyLength(),
            snapshot
        ).waitForFuture()
        var readValueFound: Int32 = 0
        var readValue: UnsafePointer<Byte>!
        var readValueLength: Int32 = 0
        try fdb_future_get_value(future.pointer, &readValueFound, &readValue, &readValueLength).orThrow()
        if commit {
            try self.commit()
        }
        guard readValueFound > 0 else {
            return nil
        }
        return readValue.getBytes(count: readValueLength)
    }

    public func clear(key: FDBKey, commit: Bool = false) throws {
        fdb_transaction_clear(self.pointer, key.asFDBKey(), key.asFDBKeyLength())
        if commit {
            try self.commit()
        }
    }

    public func clear(begin: FDBKey, end: FDBKey, commit: Bool = false) throws {
        fdb_transaction_clear_range(
            self.pointer,
            begin.asFDBKey(),
            begin.asFDBKeyLength(),
            end.asFDBKey(),
            end.asFDBKeyLength()
        )
        if commit {
            try self.commit()
        }
    }

    public func clear(range: RangeFDBKey, commit: Bool = false) throws {
        try self.clear(begin: range.begin, end: range.end, commit: commit)
    }
}
