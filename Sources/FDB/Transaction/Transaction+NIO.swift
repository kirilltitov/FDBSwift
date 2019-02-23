import CFDB
import NIO

public extension FDB.Transaction {
    public func commit() -> EventLoopFuture<Void> {
        guard let eventLoop = self.eventLoop else {
            self.debug("[commit] No event loop")
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
            self.debug("Retrying transaction (commit error \(commitError)")
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

    public func set(key: AnyFDBKey, value: Bytes, commit: Bool = false) -> EventLoopFuture<FDB.Transaction> {
        guard let eventLoop = self.eventLoop else {
            self.debug("[set] No event loop")
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }
        self.set(key: key, value: value)
        let future: EventLoopFuture<FDB.Transaction> = eventLoop.newSucceededFuture(result: self)
        if commit {
            return future
                .then { _ in self.commit() }
                .map { self }
        }
        return future
    }

    public func get(
        key: AnyFDBKey,
        snapshot: Int32 = 0,
        commit: Bool = false
    ) -> EventLoopFuture<(Bytes?, FDB.Transaction)> {
        guard let eventLoop = self.eventLoop else {
            self.debug("[get] No event loop")
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }
        let promise: EventLoopPromise<(Bytes?, FDB.Transaction)> = eventLoop.newPromise()
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
        snapshot: Int32 = 0,
        reverse: Bool = false,
        commit: Bool = false
    ) -> EventLoopFuture<(FDB.KeyValuesResult, FDB.Transaction)> {
        guard let eventLoop = self.eventLoop else {
            self.debug("[get range] No event loop")
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }
        let promise: EventLoopPromise<(FDB.KeyValuesResult, FDB.Transaction)> = eventLoop.newPromise()
        do {
            let future: Future<FDB.KeyValuesResult> = self.get(
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
        range: FDB.RangeKey,
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

    fileprivate func genericAction(
        commit: Bool,
        _ closure: () throws -> Void
    ) -> EventLoopFuture<FDB.Transaction> {
        guard let eventLoop = self.eventLoop else {
            self.debug("[generic action] No event loop")
            return FDB.dummyEventLoop.newFailedFuture(error: FDB.Error.noEventLoopProvided)
        }
        let future: EventLoopFuture<FDB.Transaction>
        do {
            try closure()
            future = eventLoop.newSucceededFuture(result: self)
        } catch {
            return eventLoop.newFailedFuture(error: error)
        }
        if commit {
            return future.then { _ in
                self.commit()
            }.map { self }
        }
        return future
    }

    public func clear(key: AnyFDBKey, commit: Bool = false) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: commit) {
            self.clear(key: key)
        }
    }

    public func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool = false) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: commit) {
            self.clear(begin: begin, end: end)
        }
    }

    public func clear(range: FDB.RangeKey, commit: Bool = false) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: commit) {
            self.clear(range: range)
        }
    }

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
    
    public func setOption(
        _ option: FDB.Transaction.Option,
        param: UnsafePointer<Byte>? = nil,
        paramLength: Int32 = 0
    ) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: false) {
            let _: FDB.Transaction = try self.setOption(option, param: param, paramLength: paramLength)
        }
    }
    
    public func setOption(
        _ option: FDB.Transaction.Option,
        param: String
    ) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: false) {
            let _: FDB.Transaction = try self.setOption(option, param: param)
        }
    }
    
    public func setOption(
        _ option: FDB.Transaction.Option,
        param: Int64
    ) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: false) {
            let _: FDB.Transaction = try self.setOption(option, param: param)
        }
    }

    public func setDebugRetryLogging(transactionName: String) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: false) {
            let _: FDB.Transaction = try self.setDebugRetryLogging(transactionName: transactionName)
        }
    }

    public func enableLogging(identifier: String) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: false) {
            let _: FDB.Transaction = try self.enableLogging(identifier: identifier)
        }
    }

    public func setTimeout(_ timeout: Int64) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: false) {
            let _: FDB.Transaction = try self.setTimeout(timeout)
        }
    }
    
    public func setRetryLimit(_ retries: Int64) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: false) {
            let _: FDB.Transaction = try self.setRetryLimit(retries)
        }
    }
    
    public func setMaxRetryDelay(_ delay: Int64) -> EventLoopFuture<FDB.Transaction> {
        return self.genericAction(commit: false) {
            let _: FDB.Transaction = try self.setRetryLimit(delay)
        }
    }
}
