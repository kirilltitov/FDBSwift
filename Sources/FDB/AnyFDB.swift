import Logging

public protocol AnyFDB {
    static var logger: Logger { get set }

    init(clusterFile: String?, networkStopTimeout: Int)
    func connect() throws
    func disconnect()

    /// NIO methods
    

    /// Sync methods
    func set(key: AnyFDBKey, value: Bytes) throws
    func setSync(key: AnyFDBKey, value: Bytes) throws
    func clear(key: AnyFDBKey) throws
    func clearSync(key: AnyFDBKey) throws
    func clear(begin: AnyFDBKey, end: AnyFDBKey) throws
    func clearSync(begin: AnyFDBKey, end: AnyFDBKey) throws
    func clear(range: FDB.RangeKey) throws
    func clear(subspace: FDB.Subspace) throws
    func get(key: AnyFDBKey, snapshot: Bool) throws -> Bytes?
    func get(subspace: FDB.Subspace, snapshot: Bool) throws -> FDB.KeyValuesResult
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
    func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes) throws
    func atomic<T: SignedInteger>(_ op: FDB.MutationType, key: AnyFDBKey, value: T) throws
    @discardableResult func increment(key: AnyFDBKey, value: Int64) throws -> Int64
    @discardableResult func decrement(key: AnyFDBKey, value: Int64) throws -> Int64
}

public extension AnyFDB {
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

    func get(key: AnyFDBKey, snapshot: Bool = false) throws -> Bytes? {
        return try self.get(key: key, snapshot: snapshot)
    }

    func get(subspace: FDB.Subspace, snapshot: Bool = false) throws -> FDB.KeyValuesResult {
        return try self.get(subspace: subspace, snapshot: snapshot)
    }

    @discardableResult func increment(key: AnyFDBKey, value: Int64 = 1) throws -> Int64 {
        return try self.increment(key: key, value: value)
    }

    @discardableResult func decrement(key: AnyFDBKey, value: Int64 = 1) throws -> Int64 {
        return try self.decrement(key: key, value: value)
    }
}
