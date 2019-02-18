import CFDB
import NIO

public extension Transaction {
    public func commit() -> EventLoopFuture<Void> {
        guard let eventLoop = self.eventLoop else {
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }
        let promise: EventLoopPromise<Future<Void>> = eventLoop.newPromise()
        do {
            let future: Future<Void> = try self.commit()
            try future.whenReady(promise.succeed)
            future.whenError(promise.fail)
        } catch {
            promise.fail(error: error)
        }
        return promise.futureResult.then { future in
            let commitError: fdb_error_t = fdb_future_get_error(future.pointer)
            if commitError == 0 {
                return eventLoop.newSucceededFuture(result: ())
            }
            let retryPromise: EventLoopPromise<Void> = eventLoop.newPromise()
            let retryFuture: Future<Void> = fdb_transaction_on_error(self.pointer, commitError).asFuture()
            do {
                try retryFuture.whenReady { _retryFuture in
                    try fdb_future_get_error(_retryFuture.pointer).orThrow()
                    throw FDB.Error.transactionRetry
                }
                retryFuture.whenError(retryPromise.fail)
            } catch {
                retryPromise.fail(error: error)
            }
            return retryPromise.futureResult
        }
    }

    public func set(key: FDBKey, value: Bytes, commit: Bool = false) -> EventLoopFuture<Transaction> {
        guard let eventLoop = self.eventLoop else {
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }
        self.set(key: key, value: value)
        let future: EventLoopFuture<Transaction> = eventLoop.newSucceededFuture(result: self)
        if commit {
            return future
                .then { _ in self.commit() }
                .map { self }
        }
        return future
    }

    public func get(key: FDBKey, snapshot: Int32 = 0, commit: Bool = false) -> EventLoopFuture<(Bytes?, Transaction)> {
        guard let eventLoop = self.eventLoop else {
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }
        let promise: EventLoopPromise<(Bytes?, Transaction)> = eventLoop.newPromise()
        do {
            let resultFuture = self.get(key: key, snapshot: snapshot)
            try resultFuture.whenReady {
                promise.succeed(result: ($0, self))
            }
            resultFuture.whenError(promise.fail)
        } catch {
            promise.fail(error: error)
        }
        let future = promise.futureResult
        if commit {
            return future
                .then { bytes in
                    self.commit().map { bytes }
                }
        }
        return future
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
    ) -> EventLoopFuture<(KeyValuesResult, Transaction)> {
        guard let eventLoop = self.eventLoop else {
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }
        let promise: EventLoopPromise<(KeyValuesResult, Transaction)> = eventLoop.newPromise()
        do {
            let future: Future<KeyValuesResult> = self.get(
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
            try future.whenReady {
                promise.succeed(result: ($0, self))
            }
            future.whenError(promise.fail)
        } catch {
            promise.fail(error: error)
        }
        let future = promise.futureResult
        if commit {
            return future.then { bytes in
                self.commit().map { bytes }
            }
        }
        return future
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
    ) -> EventLoopFuture<(KeyValuesResult, Transaction)> {
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

    fileprivate func genericAction(commit: Bool, _ closure: () -> Void) -> EventLoopFuture<Transaction> {
        guard let eventLoop = self.eventLoop else {
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }
        let future = eventLoop.newSucceededFuture(result: self)
        closure()
        if commit {
            return future.then { _ in
                self.commit()
            }.map { self }
        }
        return future
    }

    public func clear(key: FDBKey, commit: Bool = false) -> EventLoopFuture<Transaction> {
        return self.genericAction(commit: commit) {
            self.clear(key: key)
        }
    }

    public func clear(begin: FDBKey, end: FDBKey, commit: Bool = false) -> EventLoopFuture<Transaction> {
        return self.genericAction(commit: commit) {
            self.clear(begin: begin, end: end)
        }
    }

    public func clear(range: RangeFDBKey, commit: Bool = false) -> EventLoopFuture<Transaction> {
        return self.genericAction(commit: commit) {
            self.clear(range: range)
        }
    }

    public func atomic(_ op: FDB.MutationType, key: FDBKey, value: Bytes, commit: Bool = false) -> EventLoopFuture<Transaction> {
        return self.genericAction(commit: commit) {
            self.atomic(op, key: key, value: value)
        }
    }

    public func atomic<T>(_ op: FDB.MutationType, key: FDBKey, value: T, commit: Bool = false) -> EventLoopFuture<Transaction> {
        return self.genericAction(commit: commit) {
            self.atomic(op, key: key, value: getBytes(value))
        }
    }
}
