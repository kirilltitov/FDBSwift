import CFDB
import NIO

public extension FDB.Transaction {
    /// Commits current transaction
    ///
    /// - returns: EventLoopFuture with future Void value
    public func commit() -> EventLoopFuture<Void> {
        guard let eventLoop = self.eventLoop else {
            self.debug("[commit] No event loop")
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }
        let promise: EventLoopPromise<Void> = eventLoop.newPromise()

        let future: FDB.Future = self.commit()
        future.whenVoidReady(promise.succeed)
        future.whenError(promise.fail)

        return promise.futureResult
            .map { _ in () }
    }

    /// Sets bytes to given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Bytes value
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    public func set(key: AnyFDBKey, value: Bytes, commit: Bool = false) -> EventLoopFuture<FDB.Transaction> {
        guard let eventLoop = self.eventLoop else {
            self.debug("[set] No event loop")
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }

        self.set(key: key, value: value)

        var future: EventLoopFuture<FDB.Transaction> = eventLoop.newSucceededFuture(result: self)

        if commit {
            future = future
                .then { _ in self.commit() }
                .map { self }
        }

        return future
    }

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(Bytes?, FDB.Transaction)` tuple value
    public func get(
        key: AnyFDBKey,
        snapshot: Bool = false,
        commit: Bool = false
    ) -> EventLoopFuture<(Bytes?, FDB.Transaction)> {
        guard let eventLoop = self.eventLoop else {
            self.debug("[get] No event loop")
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }

        let promise: EventLoopPromise<(Bytes?, FDB.Transaction)> = eventLoop.newPromise()

        do {
            let resultFuture = self.get(key: key, snapshot: snapshot)
            try resultFuture.whenBytesReady {
                promise.succeed(result: ($0, self))
            }
            resultFuture.whenError { error in
                dump(["GET": error])
                promise.fail(error: error)
            }
        } catch {
            promise.fail(error: error)
        }

        var future = promise.futureResult

        if commit {
            future = future
                .then { bytes in
                    self.commit().map { bytes }
                }
        }

        return future
    }

    /// Returns a range of keys and their respective values in given key range
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
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(FDB.KeyValuesResult, FDB.Transaction)` tuple value
    public func get(
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
    ) -> EventLoopFuture<(FDB.KeyValuesResult, FDB.Transaction)> {
        guard let eventLoop = self.eventLoop else {
            self.debug("[get range] No event loop")
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }

        let promise: EventLoopPromise<(FDB.KeyValuesResult, FDB.Transaction)> = eventLoop.newPromise()

        do {
            let future: FDB.Future = self.get(
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
            try future.whenKeyValuesReady {
                promise.succeed(result: ($0, self))
            }
            future.whenError(promise.fail)
        } catch {
            promise.fail(error: error)
        }

        var future = promise.futureResult

        if commit {
            future = future.then { bytes in
                self.commit().map { bytes }
            }
        }

        return future
    }

    /// Returns a range of keys and their respective values in given key range
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
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future `(FDB.KeyValuesResult, FDB.Transaction)` tuple value
    public func get(
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
    ) -> EventLoopFuture<(FDB.KeyValuesResult, FDB.Transaction)> {
        return self.get(
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

    /// Performs a generic throwable closure wrapped with event loop sanity check
    ///
    /// - parameters:
    ///   - commit: Whether to commit this transaction after action or not
    ///   - closure: Throwable closure with actual business logic
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    fileprivate func genericAction(
        commit: Bool,
        _ closure: () throws -> Void
    ) -> EventLoopFuture<FDB.Transaction> {
        guard let eventLoop = self.eventLoop else {
            self.debug("[generic action] No event loop")
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }

        var future: EventLoopFuture<FDB.Transaction>

        do {
            try closure()
            future = eventLoop.newSucceededFuture(result: self)
        } catch {
            return eventLoop.newFailedFuture(error: error)
        }

        if commit {
            future = future.then { _ in
                self.commit()
            }.map { self }
        }

        return future
    }

    /// Clears given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    public func clear(key: AnyFDBKey, commit: Bool = false) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: commit) {
            self.clear(key: key)
        }
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    public func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool = false) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: commit) {
            self.clear(begin: begin, end: end)
        }
    }

    /// Clears keys in given range in FDB cluster
    ///
    /// - parameters:
    ///   - range: Range key
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    public func clear(range: FDB.RangeKey, commit: Bool = false) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: commit) {
            self.clear(range: range)
        }
    }

    /// Peforms an atomic operation in FDB cluster on given key with given value bytes
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    public func atomic(
        _ op: FDB.MutationType,
        key: AnyFDBKey,
        value: Bytes,
        commit: Bool = false
    ) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: commit) {
            self.atomic(op, key: key, value: value)
        }
    }

    /// Peforms an atomic operation in FDB cluster on given key with given generic value
    ///
    /// - parameters:
    ///   - _: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    ///   - commit: Whether to commit this transaction after action or not
    ///
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    public func atomic<T>(
        _ op: FDB.MutationType,
        key: AnyFDBKey,
        value: T,
        commit: Bool = false
    ) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: commit) {
            self.atomic(op, key: key, value: getBytes(value))
        }
    }

    /// Sets a transaction option to current transaction
    ///
    /// - parameters:
    ///   - option: Transaction option
    /// - returns: EventLoopFuture with future Transaction (`self`) value
    public func setOption(_ option: FDB.Transaction.Option) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: false) {
            let _: FDB.Transaction = try self.setOption(option)
        }
    }
}
