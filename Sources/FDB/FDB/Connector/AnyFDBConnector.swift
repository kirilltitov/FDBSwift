import LGNLog

public protocol FDBConnector {
    @available(*, deprecated, message: "Use Logger.current instead")
    static var logger: Logger { get set }

    /// Creates a new instance of FDB client with optional cluster file path and network stop timeout
    ///
    /// - parameters:
    ///   - clusterFile: path to `fdb.cluster` file. If not specified, default path (platform-specific) is chosen
    ///   - networkStopTimeout: timeout (in seconds) in which client should disconnect from FDB and stop all inner jobs
    init(clusterFile: String?, networkStopTimeout: Int)

    /// Performs explicit connection to FDB cluster
    func connect() throws

    /// Performs an explicit disconnect routine
    func disconnect()

    /// Begins a new FDB transaction
    func begin() throws -> any FDBTransaction

    /// Executes given transactional closure with appropriate retry logic
    ///
    /// Retry logic kicks in if `notCommitted` (1020) error was thrown during commit event. You must commit
    /// the transaction yourself. Additionally, this transactional closure should be idempotent in order to exclude
    /// unexpected behaviour.
    func withTransaction<T>(_ block: @escaping (any FDBTransaction) async throws -> T) async throws -> T

    /// Sets bytes to given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: bytes value
    func set(key: any FDBKey, value: Bytes) async throws

    /// Clears given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    func clear(key: any FDBKey) async throws

    /// Clears keys in given range in FDB cluster
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    func clear(begin: any FDBKey, end: any FDBKey) async throws

    /// Clears keys in given range in FDB cluster
    ///
    /// - parameters:
    ///   - range: Range key
    func clear(range: FDB.RangeKey) async throws

    /// Clears keys in given subspace in FDB cluster
    ///
    /// - parameters:
    ///   - subspace: Subspace to clear
    func clear(subspace: FDB.Subspace) async throws

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(key: any FDBKey, snapshot: Bool) async throws -> Bytes?

    /// Returns a range of keys and their respective values under given subspace
    ///
    /// - parameters:
    ///   - subspace: Subspace
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(subspace: FDB.Subspace, snapshot: Bool) async throws -> FDB.KeyValuesResult

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
    func get(
        begin: any FDBKey,
        end: any FDBKey,
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
    ) async throws -> FDB.KeyValuesResult

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
    ) async throws -> FDB.KeyValuesResult

    /// Peforms an atomic operation in FDB cluster on given key with given value bytes
    ///
    /// - parameters:
    ///   - op: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    func atomic(_ op: FDB.MutationType, key: any FDBKey, value: Bytes) async throws

    /// Peforms an atomic operation in FDB cluster on given key with given signed integer value
    ///
    /// - parameters:
    ///   - op: Atomic operation
    ///   - key: FDB key
    ///   - value: Integer
    func atomic<T: SignedInteger>(_ op: FDB.MutationType, key: any FDBKey, value: T) async throws

    /// Peforms a quasi-atomic increment operation in FDB cluster on given key with given integer
    ///
    /// Warning: though this function uses atomic `.add` increment, immediate serializable read of incremented key
    /// negates all benefits of atomicity, and therefore it shouldn't be considered truly atomical. However, it still
    /// works, and it gives you guarantees that only you will get the incremented value. It may lead to increased
    /// read conflicts on high load (hence lower performance), and is only usable when generating serial integer IDs.
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Integer
    @discardableResult
    func increment(key: any FDBKey, value: Int64) async throws -> Int64

    /// Peforms a quasi-atomic decrement operation in FDB cluster on given key with given integer
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Integer
    @discardableResult
    func decrement(key: any FDBKey, value: Int64) async throws -> Int64
}

public extension FDBConnector {
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
    func get(
        begin: any FDBKey,
        end: any FDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .wantAll,
        iteration: Int32 = 1,
        snapshot: Bool = false,
        reverse: Bool = false
    ) async throws -> FDB.KeyValuesResult {
        try await self.get(
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
    func get(
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
        reverse: Bool = false
    ) async throws -> FDB.KeyValuesResult {
        try await self.get(
            range: range,
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

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(key: any FDBKey, snapshot: Bool = false) async throws -> Bytes? {
        return try await self.get(key: key, snapshot: snapshot)
    }

    /// Returns a range of keys and their respective values under given subspace
    ///
    /// - parameters:
    ///   - subspace: Subspace
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(subspace: FDB.Subspace, snapshot: Bool = false) async throws -> FDB.KeyValuesResult {
        return try await self.get(subspace: subspace, snapshot: snapshot)
    }

    /// Peforms a quasi-atomic increment operation in FDB cluster on given key with given integer
    ///
    /// Warning: though this function uses atomic `.add` increment, immediate serializable read of incremented key
    /// negates all benefits of atomicity, and therefore it shouldn't be considered truly atomical. However, it still
    /// works, and it gives you guarantees that only you will get the incremented value. It may lead to increased
    /// read conflicts on high load (hence lower performance), and is only usable when generating serial integer IDs.
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Integer
    @discardableResult
    func increment(key: any FDBKey, value: Int64 = 1) async throws -> Int64 {
        try await self.increment(key: key, value: value)
    }

    /// Peforms a quasi-atomic decrement operation in FDB cluster on given key with given integer
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Integer
    @discardableResult
    func decrement(key: any FDBKey, value: Int64 = 1) async throws -> Int64 {
        try await self.decrement(key: key, value: value)
    }
}
