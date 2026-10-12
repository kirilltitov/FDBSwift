import CFDB
import Logging

extension FDB {
    /// A FoundationDB transaction.
    ///
    /// Transaction is a non-copyable value with a single owner and a well-defined lifetime: its resources are
    /// released exactly once, when it goes out of scope. Usually it's obtained via
    /// ``FDB/Database/withTransaction(_:)``, which lends it to the closure (it can't escape it) and handles commit
    /// and retries.
    ///
    /// Read operations return ``FDB/Future``s: the request is sent immediately, and the result is awaited later,
    /// so independent reads should be issued first and awaited afterwards to run them in parallel.
    public struct Transaction: ~Copyable {
        let pointer: OpaquePointer
        let logger: Logger
        /// Keeps the database alive for as long as the transaction exists
        let database: Database

        init(_ pointer: OpaquePointer, database: Database) {
            self.pointer = pointer
            self.database = database
            self.logger = database.logger
        }

        deinit {
            fdb_transaction_destroy(self.pointer)
        }

        /// Sets a transaction option
        public func setOption(_ option: TransactionOption) throws(FDB.Error) {
            try option.withValue { (value) throws(FDB.Error) in
                try fdb_transaction_set_option(self.pointer, option.code, value.baseAddress, Int32(value.count)).check()
            }
        }

        // MARK: - Reads

        /// Reads a value of given key, `nil` if the key doesn't exist
        ///
        /// - parameters:
        ///   - snapshot: Snapshot read, i.e. it doesn't add a read conflict range
        public func get(key: some FDB.Key, snapshot: Bool = false) -> Future<Bytes?> {
            let key = key.fdbKey
            self.trace { "Getting key \(key.printable)" }
            return .optionalBytes(fdb_transaction_get(self.pointer, key, Int32(key.count), snapshot.fdb))
        }

        /// Resolves a key selector to a key
        public func getKey(_ selector: KeySelector, snapshot: Bool = false) -> Future<Bytes> {
            .key(
                fdb_transaction_get_key(
                    self.pointer,
                    selector.key,
                    Int32(selector.key.count),
                    selector.orEqual.fdb,
                    selector.offset,
                    snapshot.fdb
                )
            )
        }

        /// Reads a single batch of key-value pairs between two key selectors.
        ///
        /// This is the low-level primitive: the result may be incomplete (see ``FDB/RangeResult/hasMore``).
        /// Use ``getAll(_:limit:snapshot:reverse:)`` or ``forEachBatch(in:limit:mode:snapshot:reverse:_:)``
        /// to read the whole range.
        ///
        /// - parameters:
        ///   - limit: Maximum number of key-value pairs to return, 0 means no limit
        ///   - targetBytes: Soft cap on the combined size of keys and values, 0 means no limit
        ///   - mode: Streaming mode
        ///   - iteration: Number of the batch when iterating in ``FDB/StreamingMode/iterator`` mode, starting from 1
        ///   - snapshot: Snapshot read, i.e. it doesn't add a read conflict range
        ///   - reverse: Return key-value pairs in reverse order
        public func getRange(
            begin: KeySelector,
            end: KeySelector,
            limit: Int = 0,
            targetBytes: Int = 0,
            mode: StreamingMode = .iterator,
            iteration: Int = 1,
            snapshot: Bool = false,
            reverse: Bool = false
        ) -> Future<RangeResult> {
            Future(
                self.rangeFuture(
                    begin: begin,
                    end: end,
                    limit: limit,
                    targetBytes: targetBytes,
                    mode: mode,
                    iteration: iteration,
                    snapshot: snapshot,
                    reverse: reverse
                )
            ) { (pointer) throws(FDB.Error) -> RangeResult in
                let batch = try KeyValueBatch(pointer)
                return RangeResult(records: batch.copyAll(), hasMore: batch.hasMore)
            }
        }

        /// Reads all key-value pairs in given range, fetching as many batches as needed
        ///
        /// - parameters:
        ///   - limit: Maximum number of key-value pairs to return, 0 means no limit
        ///   - mode: Streaming mode, ``FDB/StreamingMode/wantAll`` by default
        public func getAll(
            _ range: KeyRange,
            limit: Int = 0,
            mode: StreamingMode = .wantAll,
            snapshot: Bool = false,
            reverse: Bool = false
        ) async throws(FDB.Error) -> [KeyValue] {
            try await self.getAll(
                begin: .firstGreaterOrEqual(range.begin),
                end: .firstGreaterOrEqual(range.end),
                limit: limit,
                mode: mode,
                snapshot: snapshot,
                reverse: reverse
            )
        }

        /// Reads all key-value pairs between two key selectors, fetching as many batches as needed
        ///
        /// - parameters:
        ///   - limit: Maximum number of key-value pairs to return, 0 means no limit
        ///   - mode: Streaming mode, ``FDB/StreamingMode/wantAll`` by default
        public func getAll(
            begin: KeySelector,
            end: KeySelector,
            limit: Int = 0,
            mode: StreamingMode = .wantAll,
            snapshot: Bool = false,
            reverse: Bool = false
        ) async throws(FDB.Error) -> [KeyValue] {
            var result: [KeyValue] = []
            do {
                try await self.forEachBatch(
                    begin: begin, end: end, limit: limit, mode: mode, snapshot: snapshot, reverse: reverse
                ) { (batch: borrowing KeyValueBatch) throws(Never) in
                    result.append(contentsOf: batch.copyAll())
                }
            } catch {
                switch error {
                case let .fdb(error): throw error
                }
            }
            return result
        }

        /// Reads all key-value pairs in given range batch by batch, without copying them.
        ///
        /// Each batch is lent to the closure and is valid only within it: keys and values are exposed as
        /// `Span`s pointing directly into the memory of the FoundationDB client, so nothing is copied unless
        /// you decide to. The next batch is requested before the closure is called, so processing of a batch
        /// overlaps with fetching the next one.
        ///
        /// - parameters:
        ///   - limit: Maximum number of key-value pairs to read, 0 means no limit
        ///   - mode: Streaming mode, ``FDB/StreamingMode/iterator`` (the default) starts with small batches
        ///     and grows them as iteration goes on
        public func forEachBatch<E: Swift.Error>(
            in range: KeyRange,
            limit: Int = 0,
            mode: StreamingMode = .iterator,
            snapshot: Bool = false,
            reverse: Bool = false,
            _ body: (borrowing KeyValueBatch) throws(E) -> Void
        ) async throws(RangeError<E>) {
            try await self.forEachBatch(
                begin: .firstGreaterOrEqual(range.begin),
                end: .firstGreaterOrEqual(range.end),
                limit: limit,
                mode: mode,
                snapshot: snapshot,
                reverse: reverse,
                body
            )
        }

        /// Reads all key-value pairs between two key selectors batch by batch, without copying them.
        ///
        /// See ``forEachBatch(in:limit:mode:snapshot:reverse:_:)``.
        public func forEachBatch<E: Swift.Error>(
            begin: KeySelector,
            end: KeySelector,
            limit: Int = 0,
            mode: StreamingMode = .iterator,
            snapshot: Bool = false,
            reverse: Bool = false,
            _ body: (borrowing KeyValueBatch) throws(E) -> Void
        ) async throws(RangeError<E>) {
            var begin = begin
            var end = end
            var remaining = limit
            var iteration = 1

            var future: Future<Void>? = Future(
                self.rangeFuture(
                    begin: begin, end: end, limit: remaining, targetBytes: 0, mode: mode,
                    iteration: iteration, snapshot: snapshot, reverse: reverse
                )
            )

            while let current = future.take() {
                do {
                    try await current.waitUntilReady()
                } catch {
                    throw .fdb(error)
                }
                let batch: KeyValueBatch
                do {
                    batch = try KeyValueBatch(current.pointer)
                } catch {
                    throw .fdb(error)
                }

                if limit > 0 {
                    remaining -= batch.count
                }

                // Prefetch the next batch before handing the current one to the caller
                if batch.hasMore, batch.count > 0, limit == 0 || remaining > 0 {
                    let lastKey = batch.key(at: batch.count - 1)
                    if reverse {
                        end = .firstGreaterOrEqual(lastKey)
                    } else {
                        begin = .firstGreaterThan(lastKey)
                    }
                    iteration += 1
                    future = Future(
                        self.rangeFuture(
                            begin: begin, end: end, limit: remaining, targetBytes: 0, mode: mode,
                            iteration: iteration, snapshot: snapshot, reverse: reverse
                        )
                    )
                }

                do {
                    try body(batch)
                } catch {
                    throw .body(error)
                }

                // `current` is destroyed here, which invalidates the memory `batch` points to
                _ = consume batch
                _ = consume current
            }
        }

        /// Returns an estimation of the size of given range in bytes (based on storage server samples, so it's
        /// approximate and is meant for things like work splitting, not for exact accounting)
        public func getEstimatedRangeSizeBytes(_ range: KeyRange) -> Future<Int64> {
            .int64(
                fdb_transaction_get_estimated_range_size_bytes(
                    self.pointer, range.begin, Int32(range.begin.count), range.end, Int32(range.end.count)
                )
            )
        }

        /// Returns keys which split given range into chunks of roughly `chunkSize` bytes (the first and the last
        /// keys are the boundaries of the range itself)
        public func getRangeSplitPoints(_ range: KeyRange, chunkSize: Int64) -> Future<[Bytes]> {
            Future(
                fdb_transaction_get_range_split_points(
                    self.pointer, range.begin, Int32(range.begin.count), range.end, Int32(range.end.count), chunkSize
                )
            ) { (pointer) throws(FDB.Error) -> [Bytes] in
                var keys: UnsafePointer<FDBKey>?
                var count: Int32 = 0
                try fdb_future_get_key_array(pointer, &keys, &count).check()
                guard count > 0, let keys else {
                    return []
                }
                // `FDBKey` is declared with `#pragma pack(4)`, so elements may be misaligned for Swift
                let raw = UnsafeRawPointer(keys)
                return (0 ..< Int(count)).map { index in
                    let key = raw.loadUnaligned(fromByteOffset: index * MemoryLayout<FDBKey>.stride, as: FDBKey.self)
                    return Bytes(UnsafeBufferPointer(start: key.key, count: Int(key.key_length)))
                }
            }
        }

        /// Returns the version at which the transaction was committed.
        ///
        /// Only valid after a successful commit; a read-only transaction returns `-1`.
        public func getCommittedVersion() throws(FDB.Error) -> Int64 {
            var version: Int64 = 0
            try fdb_transaction_get_committed_version(self.pointer, &version).check()
            return version
        }

        /// Returns the read version of this transaction
        public func getReadVersion() -> Future<Int64> {
            .int64(fdb_transaction_get_read_version(self.pointer))
        }

        /// Sets the read version of this transaction
        public func setReadVersion(_ version: Int64) {
            fdb_transaction_set_read_version(self.pointer, version)
        }

        /// Watches given key for changes.
        ///
        /// The watch becomes active only after the transaction is committed, and it outlives the transaction:
        /// return the future from ``FDB/Database/withTransaction(_:)`` and await it afterwards. It completes when the
        /// value of the key differs from the one this transaction has seen (or written).
        ///
        /// Keep in mind that:
        /// - a completed watch means that the value has *probably* changed: intermediate changes may be missed
        ///   (`A → B → A` may not trigger it), so re-read the value afterwards;
        /// - if the transaction isn't committed (or fails), the watch fails too;
        /// - the number of outstanding watches is limited per database (``FDB/DatabaseOption/maxWatches(_:)``,
        ///   10 000 by default), exceeding it fails with ``FDB/Error/tooManyWatches``;
        /// - a watch which is no longer needed should be dropped (or cancelled), which cancels it in the cluster.
        ///
        /// Prefer ``FDB/Database/changes(of:)`` or ``FDB/Database/waitForChange(of:)``, which handle all of that.
        public func watch(key: some FDB.Key) -> Future<Void> {
            let key = key.fdbKey
            self.trace { "Watching key \(key.printable)" }
            return Future(fdb_transaction_watch(self.pointer, key, Int32(key.count)))
        }

        /// Returns an estimation of the transaction size in bytes so far
        public func getApproximateSize() -> Future<Int64> {
            .int64(fdb_transaction_get_approximate_size(self.pointer))
        }

        // MARK: - Writes

        /// Sets the value of given key
        public func set(key: some FDB.Key, value: Bytes) {
            let key = key.fdbKey
            self.trace { "Setting \(value.count) bytes to key \(key.printable)" }
            fdb_transaction_set(self.pointer, key, Int32(key.count), value, Int32(value.count))
        }

        /// Sets the value of a key which contains an incomplete versionstamp (see ``FDB/Versionstamp``).
        ///
        /// The versionstamp is filled in by the cluster on commit. Use
        /// ``FDB/Database/withVersionstampedTransaction(_:)`` to learn it.
        public func set(versionstampedKey key: some FDB.Key, value: Bytes) throws(FDB.Error) {
            guard let offset = try key.incompleteVersionstampOffset() else {
                throw FDB.Error.missingIncompleteVersionstamp
            }
            var key = key.fdbKey
            withUnsafeBytes(of: UInt32(offset).littleEndian) { key.append(contentsOf: $0) }
            self.atomic(.setVersionstampedKey, key: key, value: value)
        }

        /// Clears given key
        public func clear(key: some FDB.Key) {
            let key = key.fdbKey
            self.trace { "Clearing key \(key.printable)" }
            fdb_transaction_clear(self.pointer, key, Int32(key.count))
        }

        /// Clears all keys in given range
        public func clear(range: KeyRange) {
            self.trace { "Clearing range \(range.begin.printable) ..< \(range.end.printable)" }
            fdb_transaction_clear_range(
                self.pointer, range.begin, Int32(range.begin.count), range.end, Int32(range.end.count)
            )
        }

        /// Performs an atomic operation
        public func atomic(_ op: MutationType, key: some FDB.Key, value: Bytes) {
            let key = key.fdbKey
            self.trace { "Atomic \(op) on key \(key.printable)" }
            fdb_transaction_atomic_op(
                self.pointer, key, Int32(key.count), value, Int32(value.count), FDBMutationType(op.rawValue)
            )
        }

        /// Performs an atomic operation with an integer parameter (encoded as little-endian)
        public func atomic(_ op: MutationType, key: some FDB.Key, value: some FixedWidthInteger) {
            self.atomic(op, key: key, value: withUnsafeBytes(of: value.littleEndian) { Bytes($0) })
        }

        /// Adds a read conflict range, as if given range was read
        public func addReadConflict(range: KeyRange) throws(FDB.Error) {
            try self.addConflict(range: range, type: FDB_CONFLICT_RANGE_TYPE_READ)
        }

        /// Adds a read conflict range for a single key, as if it was read
        public func addReadConflict(key: some FDB.Key) throws(FDB.Error) {
            let key = key.fdbKey
            try self.addReadConflict(range: KeyRange(begin: key, end: key + [0x00]))
        }

        /// Adds a write conflict range for a single key, as if it was written
        public func addWriteConflict(key: some FDB.Key) throws(FDB.Error) {
            let key = key.fdbKey
            try self.addWriteConflict(range: KeyRange(begin: key, end: key + [0x00]))
        }

        /// Adds a write conflict range, as if given range was written
        public func addWriteConflict(range: KeyRange) throws(FDB.Error) {
            try self.addConflict(range: range, type: FDB_CONFLICT_RANGE_TYPE_WRITE)
        }

        // MARK: - Lifecycle

        /// Commits the transaction.
        ///
        /// Not needed with ``FDB/Database/withTransaction(_:)``, which commits automatically.
        public func commit() -> Future<Void> {
            self.trace { "Committing" }
            return Future(fdb_transaction_commit(self.pointer))
        }

        /// Returns a future versionstamp of this transaction, which becomes available after it's committed.
        ///
        /// Must be called before commit.
        public func getVersionstamp() -> Future<Versionstamp> {
            Future(fdb_transaction_get_versionstamp(self.pointer)) { (pointer) throws(FDB.Error) -> Versionstamp in
                var key: UnsafePointer<UInt8>?
                var length: Int32 = 0
                try fdb_future_get_key(pointer, &key, &length).check()
                guard length == 10, let key else {
                    throw FDB.Error.invalidVersionstamp
                }
                return Versionstamp(bytes: UnsafeRawBufferPointer(start: key, count: 10))
            }
        }

        /// Determines whether given error is retryable and prepares the transaction for a retry:
        /// the future throws if the error is not retryable (or the retry limit is reached), and succeeds after a
        /// backoff delay otherwise.
        public func onError(_ error: FDB.Error) -> Future<Void> {
            Future(fdb_transaction_on_error(self.pointer, error.code))
        }

        /// Resets the transaction to its initial state
        public func reset() {
            fdb_transaction_reset(self.pointer)
        }

        /// Cancels the transaction. All pending and future operations fail with ``FDB/Error/transactionCancelled``.
        public func cancel() {
            fdb_transaction_cancel(self.pointer)
        }

        // MARK: - Private

        private func rangeFuture(
            begin: KeySelector,
            end: KeySelector,
            limit: Int,
            targetBytes: Int,
            mode: StreamingMode,
            iteration: Int,
            snapshot: Bool,
            reverse: Bool
        ) -> OpaquePointer {
            self.trace { "Getting range \(begin.key.printable) ..< \(end.key.printable) (iteration \(iteration))" }
            return fdb_transaction_get_range(
                self.pointer,
                begin.key, Int32(begin.key.count), begin.orEqual.fdb, begin.offset,
                end.key, Int32(end.key.count), end.orEqual.fdb, end.offset,
                Int32(clamping: limit),
                Int32(clamping: targetBytes),
                FDBStreamingMode(mode.rawValue),
                Int32(clamping: iteration),
                snapshot.fdb,
                reverse.fdb
            )
        }

        private func addConflict(range: KeyRange, type: FDBConflictRangeType) throws(FDB.Error) {
            try fdb_transaction_add_conflict_range(
                self.pointer, range.begin, Int32(range.begin.count), range.end, Int32(range.end.count), type
            ).check()
        }

        @inline(__always)
        private func trace(_ message: () -> String) {
            if self.logger.logLevel <= .trace {
                self.logger.trace("\(message())")
            }
        }
    }

    /// Error of ``FDB/Transaction/forEachBatch(in:limit:mode:snapshot:reverse:_:)``:
    /// either a FoundationDB error or an error thrown by the closure
    public enum RangeError<Body: Swift.Error>: Swift.Error, FDB.ErrorWrapper {
        case fdb(FDB.Error)
        case body(Body)

        public var underlyingFDBError: FDB.Error? {
            switch self {
            case let .fdb(error): error
            case let .body(error): (error as? FDB.Error) ?? (error as? any FDB.ErrorWrapper)?.underlyingFDBError
            }
        }
    }
}

extension FDB {
    /// An error which may wrap an ``FDB/Error``.
    ///
    /// ``FDB/Database/withTransaction(_:)`` unwraps such errors to decide whether to retry the transaction.
    public protocol ErrorWrapper: Swift.Error {
        var underlyingFDBError: FDB.Error? { get }
}
}

extension Bool {
    @inline(__always)
    var fdb: fdb_bool_t {
        self ? 1 : 0
    }
}

extension Array where Element == UInt8 {
    /// Printable representation of arbitrary bytes for logging purposes: printable ASCII is kept as is,
    /// everything else is rendered as `\xNN`. Never traps.
    var printable: String {
        var result = ""
        result.reserveCapacity(self.count)
        for byte in self {
            if byte >= 0x20 && byte < 0x7F && byte != UInt8(ascii: "\\") {
                result.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                let hex = String(byte, radix: 16, uppercase: true)
                result += byte < 0x10 ? "\\x0\(hex)" : "\\x\(hex)"
            }
        }
        return result
    }
}
