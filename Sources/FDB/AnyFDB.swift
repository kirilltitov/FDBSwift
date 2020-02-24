import Logging
import NIO

public protocol AnyFDB {
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

    /// Begins a new FDB transaction without an event loop
    func begin() throws -> AnyFDBTransaction

    /// Begins a new FDB transaction with given event loop
    ///
    /// - parameters:
    ///   - eventLoop: Swift-NIO EventLoop to run future computations
    /// - returns: `EventLoopFuture` with a transaction instance as future value.
    func begin(on eventLoop: EventLoop) -> EventLoopFuture<AnyFDBTransaction>

    /// Executes given transactional closure with appropriate retry logic
    ///
    /// Retry logic kicks in if `notCommitted` (1020) error was thrown during commit event. You must commit
    /// the transaction yourself. Additionally, this transactional closure should be idempotent in order to exclude
    /// unexpected behaviour.
    func withTransaction<T>(
        on eventLoop: EventLoop,
        _ block: @escaping (AnyFDBTransaction) throws -> EventLoopFuture<T>
    ) -> EventLoopFuture<T>

    /// Executes given transactional closure with appropriate retry logic
    ///
    /// This function will block current thread during execution
    ///
    /// Retry logic kicks in if `notCommitted` (1020) error was thrown during commit event. You must commit
    /// the transaction yourself. Additionally, this transactional closure should be idempotent in order to exclude
    /// unexpected behaviour.
    func withTransaction<T>(_ block: @escaping (AnyFDBTransaction) throws -> T) throws -> T

    /// Sets bytes to given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: bytes value
    func set(key: AnyFDBKey, value: Bytes) throws

    /// Sets bytes to given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: bytes value
    func setSync(key: AnyFDBKey, value: Bytes) throws

    /// Clears given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    func clear(key: AnyFDBKey) throws

    /// Clears given key in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    func clearSync(key: AnyFDBKey) throws

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    func clear(begin: AnyFDBKey, end: AnyFDBKey) throws

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    func clearSync(begin: AnyFDBKey, end: AnyFDBKey) throws

    /// Clears keys in given range in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - range: Range key
    func clear(range: FDB.RangeKey) throws

    /// Clears keys in given subspace in FDB cluster
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - subspace: Subspace to clear
    func clear(subspace: FDB.Subspace) throws

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(key: AnyFDBKey, snapshot: Bool) throws -> Bytes?

    /// Returns a range of keys and their respective values under given subspace
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - subspace: Subspace
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(subspace: FDB.Subspace, snapshot: Bool) throws -> FDB.KeyValuesResult

    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
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
    ) throws -> FDB.KeyValuesResult

    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
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
    ) throws -> FDB.KeyValuesResult

    /// Peforms an atomic operation in FDB cluster on given key with given value bytes
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - op: Atomic operation
    ///   - key: FDB key
    ///   - value: Value bytes
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes) throws

    /// Peforms an atomic operation in FDB cluster on given key with given signed integer value
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - op: Atomic operation
    ///   - key: FDB key
    ///   - value: Integer
    func atomic<T: SignedInteger>(_ op: FDB.MutationType, key: AnyFDBKey, value: T) throws

    /// Peforms a quasi-atomic increment operation in FDB cluster on given key with given integer
    ///
    /// This function will block current thread during execution
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
    func increment(key: AnyFDBKey, value: Int64) throws -> Int64

    /// Peforms a quasi-atomic decrement operation in FDB cluster on given key with given integer
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Integer
    @discardableResult
    func decrement(key: AnyFDBKey, value: Int64) throws -> Int64
}

public extension AnyFDB {
    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
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
        reverse: Bool = false
    ) throws -> FDB.KeyValuesResult {
        return try self.get(
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
    /// This function will block current thread during execution
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
    ) throws -> FDB.KeyValuesResult {
        return try self.get(
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
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(key: AnyFDBKey, snapshot: Bool = false) throws -> Bytes? {
        return try self.get(key: key, snapshot: snapshot)
    }

    /// Returns a range of keys and their respective values under given subspace
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - subspace: Subspace
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(subspace: FDB.Subspace, snapshot: Bool = false) throws -> FDB.KeyValuesResult {
        return try self.get(subspace: subspace, snapshot: snapshot)
    }

    /// Peforms a quasi-atomic increment operation in FDB cluster on given key with given integer
    ///
    /// This function will block current thread during execution
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
    func increment(key: AnyFDBKey, value: Int64 = 1) throws -> Int64 {
        return try self.increment(key: key, value: value)
    }

    /// Peforms a quasi-atomic decrement operation in FDB cluster on given key with given integer
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: Integer
    @discardableResult
    func decrement(key: AnyFDBKey, value: Int64 = 1) throws -> Int64 {
        return try self.decrement(key: key, value: value)
    }
}
