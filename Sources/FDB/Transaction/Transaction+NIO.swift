import CFDB
import NIO

internal extension EventLoopFuture {
    @usableFromInline
    func checkingRetryableError(for transaction: AnyFDBTransaction) -> EventLoopFuture {
        return self.flatMapError { error in
            guard
                let FDBError = error as? FDB.Error,
                let realTransaction = transaction as? FDB.Transaction
            else {
                return self.eventLoop.makeFailedFuture(error)
            }

            let onErrorFuture: FDB.Future = fdb_transaction_on_error(realTransaction.pointer, FDBError.errno).asFuture()

            let promise: EventLoopPromise<Value> = self.eventLoop.makePromise()

            onErrorFuture.whenVoidReady {
                promise.fail(FDB.Error.transactionRetry(transaction: transaction))
            }
            onErrorFuture.whenError(promise.fail)

            return promise.futureResult
        }
    }
}

public extension FDB.Transaction {
    func commit() -> EventLoopFuture<Void> {
        guard let eventLoop = self.eventLoop else {
            self.log("[commit] No event loop", level: .error)
            return FDB.dummyEventLoop.makeFailedFuture(FDB.Error.noEventLoopProvided)
        }
        let promise: EventLoopPromise<Void> = eventLoop.makePromise()

        let future: FDB.Future = self.commit()
        future.whenVoidReady(promise.succeed)
        future.whenError(promise.fail)

        return promise.futureResult.map { _ in () }
    }

    func set(key: AnyFDBKey, value: Bytes, commit: Bool) -> EventLoopFuture<AnyFDBTransaction> {
        guard let eventLoop = self.eventLoop else {
            self.log("[set] No event loop", level: .error)
            return FDB.dummyEventLoop.makeFailedFuture(FDB.Error.noEventLoopProvided)
        }

        self.set(key: key, value: value)

        var future: EventLoopFuture<AnyFDBTransaction> = eventLoop.makeSucceededFuture(self)

        if commit {
            future = future
                .flatMap { $0.commit() }
                .map { self }
        }

        return future
    }

    func set(versionstampedKey: AnyFDBKey, value: Bytes, commit: Bool) -> EventLoopFuture<AnyFDBTransaction> {
        guard let eventLoop = self.eventLoop else {
            self.log("[set versionstampedKey] No event loop", level: .error)
            return FDB.dummyEventLoop.makeFailedFuture(FDB.Error.noEventLoopProvided)
        }

        do {
            var serializedKey = versionstampedKey.asFDBKey()
            let offset = try FDB.Tuple.offsetOfFirstIncompleteVersionstamp(from: serializedKey)
            serializedKey.append(contentsOf: getBytes(offset.littleEndian))
            
            return self.atomic(.setVersionstampedKey, key: serializedKey, value: value, commit: commit)
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }

    func get(
        key: AnyFDBKey,
        snapshot: Bool,
        commit: Bool
    ) -> EventLoopFuture<Bytes?> {
        guard let eventLoop = self.eventLoop else {
            self.log("[get] No event loop", level: .error)
            return FDB.dummyEventLoop.makeFailedFuture(FDB.Error.noEventLoopProvided)
        }

        let promise: EventLoopPromise<Bytes?> = eventLoop.makePromise()

        do {
            let resultFuture = self.get(key: key, snapshot: snapshot)
            try resultFuture.whenBytesReady {
                promise.succeed($0)
            }
            resultFuture.whenError(promise.fail)
        } catch {
            promise.fail(error)
        }

        var future = promise.futureResult

        if commit {
            future = future.flatMap { maybeBytes in
                self
                    .commit()
                    .map { maybeBytes }
            }
        }

        return future
    }

    func get(
        key: AnyFDBKey,
        snapshot: Bool,
        commit: Bool
    ) -> EventLoopFuture<(Bytes?, AnyFDBTransaction)> {
        return self
            .get(key: key, snapshot: snapshot, commit: commit)
            .map { ($0, self) }
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
    ) -> EventLoopFuture<FDB.KeyValuesResult> {
        guard let eventLoop = self.eventLoop else {
            self.log("[get range] No event loop", level: .error)
            return FDB.dummyEventLoop.makeFailedFuture(FDB.Error.noEventLoopProvided)
        }

        let promise: EventLoopPromise<FDB.KeyValuesResult> = eventLoop.makePromise()

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
                promise.succeed($0)
            }
            future.whenError(promise.fail)
        } catch {
            promise.fail(error)
        }

        var future = promise.futureResult

        if commit {
            future = future.flatMap { result in
                self.commit().map { result }
            }
        }

        return future
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
        ).map { ($0, self) }
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
    ) -> EventLoopFuture<FDB.KeyValuesResult> {
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
    ) -> EventLoopFuture<(FDB.KeyValuesResult, AnyFDBTransaction)> {
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
        ).map { ($0, self) }
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
    ) -> EventLoopFuture<AnyFDBTransaction> {
        guard let eventLoop = self.eventLoop else {
            self.log("[generic action] No event loop", level: .error)
            return FDB.dummyEventLoop.makeFailedFuture(FDB.Error.noEventLoopProvided)
        }

        var future: EventLoopFuture<AnyFDBTransaction>

        do {
            try closure()
            future = eventLoop.makeSucceededFuture(self)
        } catch {
            return eventLoop.makeFailedFuture(error)
        }

        if commit {
            future = future.flatMap { _ in
                self.commit()
            }.map { self }
        }

        return future
    }

    func clear(key: AnyFDBKey, commit: Bool) -> EventLoopFuture<AnyFDBTransaction> {
        return self.genericAction(commit: commit) {
            self.clear(key: key)
        }
    }

    func clear(begin: AnyFDBKey, end: AnyFDBKey, commit: Bool) -> EventLoopFuture<AnyFDBTransaction> {
        return self.genericAction(commit: commit) {
            self.clear(begin: begin, end: end)
        }
    }

    func clear(range: FDB.RangeKey, commit: Bool) -> EventLoopFuture<AnyFDBTransaction> {
        return self.genericAction(commit: commit) {
            self.clear(range: range)
        }
    }

    func atomic(
        _ op: FDB.MutationType,
        key: AnyFDBKey,
        value: Bytes,
        commit: Bool
    ) -> EventLoopFuture<AnyFDBTransaction> {
        return self.genericAction(commit: commit) {
            self.atomic(op, key: key, value: value)
        }
    }

    func atomic<T>(
        _ op: FDB.MutationType,
        key: AnyFDBKey,
        value: T,
        commit: Bool
    ) -> EventLoopFuture<AnyFDBTransaction> {
        return self.genericAction(commit: commit) {
            self.atomic(op, key: key, value: getBytes(value))
        }
    }

    func setOption(_ option: FDB.Transaction.Option) -> EventLoopFuture<AnyFDBTransaction> {
        return self.genericAction(commit: false) {
            let _: AnyFDBTransaction = try self.setOption(option)
        }
    }

    func getReadVersion() -> EventLoopFuture<Int64> {
        guard let eventLoop = self.eventLoop else {
            self.log("[getReadVersion] No event loop", level: .error)
            return FDB.dummyEventLoop.makeFailedFuture(FDB.Error.noEventLoopProvided)
        }

        let promise: EventLoopPromise<Int64> = eventLoop.makePromise()

        let future: FDB.Future = self.getReadVersion()
        future.whenError(promise.fail)

        do {
            try future.whenInt64Ready(promise.succeed)
        } catch {
            promise.fail(error)
        }

        return promise.futureResult
    }
    
    /// Returns a future for the versionstamp which was used by any versionstamp operations
    /// in this transaction. Unlike the synchronous version of the same name, this method
    /// does _not_ commit by default.
    ///
    /// - returns: EventLoopFuture with future FDB.Versionstamp value
    func getVersionstamp() -> EventLoopFuture<FDB.Versionstamp> {
        return getVersionstamp(commit: false)
    }
    
    /// Returns a future for the versionstamp which was used by any versionstamp operations
    /// in this transaction, and optionally commit the transaction right afterwards
    ///
    /// - returns: EventLoopFuture with future FDB.Versionstamp value
    func getVersionstamp(commit shouldCommit: Bool) -> EventLoopFuture<FDB.Versionstamp> {
        guard let eventLoop = self.eventLoop else {
            self.log("[getVersionstamp] No event loop", level: .error)
            return FDB.dummyEventLoop.makeFailedFuture(FDB.Error.noEventLoopProvided)
        }

        let promise: EventLoopPromise<FDB.Versionstamp> = eventLoop.makePromise()
        
        let future: FDB.Future = self.getVersionstamp()
        future.whenError { (error) in
            promise.fail(error)
        }
        
        do {
            try future.whenKeyBytesReady { bytes in
                guard bytes.count == 10 else {
                    self.log("[getVersionstamp] Bytes that do not represent a versionstamp were returned: \(String(describing: bytes))", level: .error)
                    promise.fail(FDB.Error.invalidVersionstamp)
                    return
                }
                
                let transactionCommitVersion = try! UInt64(bigEndian: Bytes(bytes[0..<8]).cast())
                let batchNumber = try! UInt16(bigEndian: Bytes(bytes[8..<10]).cast())
                
                let versionstamp = FDB.Versionstamp(transactionCommitVersion: transactionCommitVersion, batchNumber: batchNumber)
                promise.succeed(versionstamp)
            }
        } catch {
            promise.fail(error)
        }
        
        if shouldCommit {
            return self.commit().flatMap { promise.futureResult }
        } else {
            return promise.futureResult
        }
    }
}
