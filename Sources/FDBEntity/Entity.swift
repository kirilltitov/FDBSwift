import FDB
import Helpers
import MessagePack
import Foundation

public extension FDB {
    enum Entity {}
}

public extension FDB.Entity {
    /// Serialization format
    enum Format: String, CaseIterable {
        case JSON, MsgPack
    }
}

public protocol FDBEntity: Codable {
    /// Type of ID field of entity
    associatedtype Identifier: AnyIdentifier, FDBTuplePackable

    /// Path to ID field
    typealias IDKeyPath = KeyPath<Self, Identifier>

    /// Serialization format for all entities of this kind
    static var format: FDB.Entity.Format { get }

    /// Storage
    static var storage: any FDBConnector { get }

    /// Root application FDB Subspace — `/[root_subspace]`
    static var subspace: FDB.Subspace { get }

    /// Entity name for identifying in DB
    ///
    /// Default implementation: current class name
    static var entityName: String { get }

    /// Flag indicating whether to use full class name as `entityName` in default implementation
    /// (including module name and preceding namespace)
    ///
    /// Default implementation: `false`
    static var fullEntityName: Bool { get }

    /// Path to ID property
    static var IDKey: IDKeyPath { get }

    /// Initializes an Entita2 model from serialized bytes in given format
    init(from bytes: Bytes, format: FDB.Entity.Format) throws

    /// Packs current model into given format bytes
    func pack(to format: FDB.Entity.Format) throws -> Bytes

    /// Tries to load an entity from storage by given ID
    static func load(by ID: Identifier, within transaction: (any FDBTransaction)?) async throws -> Self?

    /// Tries to load an entity from storage by given ID raw bytes within given transaction.
    /// For details and format of raw ID see `Self.IDBytesAsKey`
    static func loadByRaw(IDBytes: Bytes, within transaction: (any FDBTransaction)?) async throws -> Self?

    /// Executes some system routines after successful entity load.
    /// Do not define or execute this method, instead go for `afterLoad`
    func afterLoad0(within transaction: any FDBTransaction) async throws

    /// Executes some routines after successful entity load.
    /// You may define this method in order to implement custom logic
    func afterLoad(within transaction: any FDBTransaction) async throws

    /// Same as `save`, but assuming new record,
    /// executes `beforeInsert` and `afterInsert` before and after insert respectively.
    func insert(within transaction: (any FDBTransaction)?, commit: Bool) async throws

    /// Saves current entity (new or existing) to storage and optionally commits given transaction if possible
    func save(within transaction: (any FDBTransaction)?, commit: Bool) async throws

    /// Saves current entity to storage by given identifier and optionally commits current transaction if possible
    func save(by ID: Identifier?, within transaction: (any FDBTransaction)?, commit: Bool) async throws

    /// Deletes current entity from storage and optionally commits current transaction if possible
    func delete(within transaction: (any FDBTransaction)?, commit: Bool) async throws

    /// Executes some system routines for saving the entity to storage
    /// Do not define or execute this method
    func save0(by ID: Identifier?, within transaction: any FDBTransaction) throws

    /// Executes some system routines for deleting the entity from the storage
    /// Do not define or execute this method
    func delete0(within transaction: any FDBTransaction)

    /// Executes some system routines before inserting an entity.
    /// Do not define or execute this method
    func beforeInsert0(within transaction: any FDBTransaction) async throws

    /// Executes some routines before inserting an entity.
    /// Do execute this method
    func beforeInsert(within transaction: any FDBTransaction) async throws

    /// Executes some routines after inserting an entity.
    /// Do execute this method
    func afterInsert(within transaction: any FDBTransaction) async throws

    /// Executes some system routines after inserting an entity.
    /// Do not define or execute this method
    func afterInsert0(within transaction: any FDBTransaction) async throws

    /// Executes some system routines before saving an entity.
    /// Do not define or execute this method
    func beforeSave0(within transaction: any FDBTransaction) async throws

    /// Executes some routines before saving an entity.
    /// Do not execute this method
    func beforeSave(within transaction: any FDBTransaction) async throws

    /// Executes some routines after saving an entity.
    /// Do not execute this method
    func afterSave(within transaction: any FDBTransaction) async throws

    /// Executes some system routines after saving an entity.
    /// Do not define or execute this method
    func afterSave0(within transaction: any FDBTransaction) async throws

    /// Executes some system routines before deleting an entity.
    /// Do not define or execute this method
    func beforeDelete0(within transaction: any FDBTransaction) async throws

    /// Executes some routines before deleting an entity.
    /// Do not execute this method
    func beforeDelete(within transaction: any FDBTransaction) async throws

    /// Executes some routines after deleting an entity.
    /// Do not execute this method
    func afterDelete(within transaction: any FDBTransaction) async throws

    /// Executes some system routines after deleting an entity.
    /// Do not define or execute this method
    func afterDelete0(within transaction: any FDBTransaction) async throws

    /// Returns an ID of current entity
    func getID() -> Identifier

    /// Returns ID bytes of current entity
    func getIDAsKey() -> Bytes

    /// Converts given bytes to key bytes
    static func IDBytesAsKey(bytes: Bytes) -> Bytes

    /// Converts given identifier to key bytes
    static func IDAsKey(ID: Identifier) -> Bytes
}

public extension FDBEntity {
    func getID() -> Identifier {
        self[keyPath: Self.IDKey]
    }

    @inlinable
    static func IDBytesAsKey(bytes: Bytes) -> Bytes {
        Self.subspacePrefix[bytes].asFDBKey()
    }

    @inlinable
    static func IDAsKey(ID: Identifier) -> Bytes {
        Self.subspacePrefix[ID].asFDBKey()
    }

    static func doesRelateToThis(tuple: FDB.Tuple) -> Bool {
        let flat = tuple.tuple.compactMap { $0 }
        guard flat.count >= 2 else {
            return false
        }
        guard let value = flat[flat.count - 2] as? String, value == self.entityName else {
            return false
        }
        return true
    }

    @usableFromInline
    internal static func unwrapTransactionOrBegin(maybeTransaction: (any FDBTransaction)?) throws -> FDBTransaction {
        try (maybeTransaction ?? self.storage.begin())
    }

    @inlinable
    func getIDAsKey() -> Bytes {
        Self.IDAsKey(ID: self.getID())
    }

    /// Current entity-related FDB Subspace — `/[root_subspace]/[entity_name]`
    static var subspacePrefix: FDB.Subspace {
        self.subspace[self.entityName]
    }

    /// Tries to load an entity for given ID within a given transaction (optional)
    @inlinable
    static func load(
        by ID: Identifier,
        within transaction: (any FDBTransaction)? = nil,
        snapshot: Bool
    ) async throws -> Self? {
        let transaction = try Self.unwrapTransactionOrBegin(transaction)

        let maybeBytes = try await transaction.get(key: Self.IDAsKey(ID: ID), snapshot: snapshot)

        return try await self.afterLoadRoutines0(
            maybeBytes: maybeBytes,
            within: transaction
        )
    }

    /// Loads all entities in given subspace within a given transaction (optional)
    @inlinable
    static func loadAll(
        bySubspace subspace: FDB.Subspace,
        limit: Int32 = 0, // todo: this is virtually useless without proper windowing
        within transaction: (any FDBTransaction)? = nil,
        snapshot: Bool
    ) async throws -> [(ID: Self.Identifier, value: Self)] {
        let transaction = try Self.unwrapTransactionOrBegin(transaction)

        let results = try await transaction.get(
            range: subspace.range,
            limit: limit,
            snapshot: snapshot
        )

        return try results.records.map {
            let instance = try Self(from: $0.value, format: Self.format)
            return (
                ID: instance.getID(),
                value: instance
            )
        }
    }

    /// Loads all entities in DB within a given transaction (optional)
    @inlinable
    static func loadAll(
        limit: Int32 = 0,
        within transaction: (any FDBTransaction)? = nil,
        snapshot: Bool
    ) async throws -> [(ID: Self.Identifier, value: Self)] {
        try await Self.loadAll(
            bySubspace: Self.subspacePrefix,
            limit: limit,
            within: transaction,
            snapshot: snapshot
        )
    }

    /// Loads all entities for given key within a given transaction (optional)
    @inlinable
    static func loadAll(
        by key: any FDBKey,
        limit: Int32 = 0,
        within transaction: (any FDBTransaction)? = nil,
        snapshot: Bool
    ) async throws -> [(ID: Self.Identifier, value: Self)] {
        try await Self.loadAll(
            bySubspace: Self.subspacePrefix[key],
            limit: limit,
            within: transaction,
            snapshot: snapshot
        )
    }
}

public extension FDBEntity {
    init(from bytes: Bytes, format: FDB.Entity.Format = Self.format) throws {
        let data = Data(bytes)

        let result: Self
        switch format {
        case .JSON: result = try JSONDecoder().decode(Self.self, from: data)
        case .MsgPack: result = try MessagePackDecoder().decode(Self.self, from: data)
        }
        self = result
    }

    func pack(to format: FDB.Entity.Format = Self.format) throws -> Bytes {
        let result: Bytes
        switch format {
        case .JSON: result = try Bytes(JSONEncoder().encode(self))
        case .MsgPack: result = try Bytes(MessagePackEncoder().encode(self))
        }
        return result
    }
}
