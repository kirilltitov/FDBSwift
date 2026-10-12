public import FDB
import Foundation
import MessagePack

extension FDB {
    /// A `Codable` entity stored in FoundationDB by its ID.
    ///
    /// Entities of a type are stored under `subspace/entityName/ID`, serialized with ``format``:
    ///
    /// ```swift
    /// struct User: FDB.Entity {
    ///     static let storage: any FDB.Transactor = db // or a tenant
    ///     static let subspace = FDB.Subspace("app")
    ///     static var IDKey: KeyPath<User, FDB.UUID> { \.ID }
    ///
    ///     let ID: FDB.UUID
    ///     var name: String
    /// }
    ///
    /// try await User(ID: FDB.UUID(), name: "Kirill").insert()
    /// try await User.storage.withTransaction { tr in
    ///     guard var user = try await User.load(by: id, within: tr) else { return }
    ///     user.name = "New name"
    ///     try await user.save(within: tr)
    /// }
    /// ```
    ///
    /// Operations take a transaction (`within:`), so that several of them are atomic. Each one also has a variant
    /// without it, running in its own transaction.
    ///
    /// Hooks (`beforeSave`, `afterLoad` etc.) run within the operation's transaction. Transactions are retried on
    /// conflicts, so hooks must not have side effects outside of the database.
    public protocol Entity: Codable {
        /// Type of the ID: any tuple-packable type, like `Int`, `String` or ``FDB/UUID``
        associatedtype Identifier: Hashable & Sendable & FDB.TuplePackable

        /// Path to the ID property
        typealias IDKeyPath = KeyPath<Self, Identifier>

        /// Database (or tenant) the entities are stored in
        static var storage: any FDB.Transactor { get }

        /// Root subspace of entities
        static var subspace: FDB.Subspace { get }

        /// Serialization format, JSON by default
        static var format: FDB.EntityFormat { get }

        /// Name of the entity in keys. Default implementation: the type name (see ``fullEntityName``)
        static var entityName: String { get }

        /// Whether the default ``entityName`` is the full type name (including the module and enclosing types).
        /// `false` by default.
        static var fullEntityName: Bool { get }

        /// Path to the ID property.
        ///
        /// Declare it as a computed property (`static var IDKey: KeyPath<User, Int> { \.ID }`): key paths are not
        /// `Sendable`, so a stored static one is not concurrency-safe.
        static var IDKey: IDKeyPath { get }

        /// Key of the entity with given ID. Default implementation: `subspace/entityName/ID`
        static func IDAsKey(ID: Identifier) -> Bytes

        /// Key of the entity with given raw ID bytes. Default implementation: `subspace/entityName/bytes`
        static func IDBytesAsKey(bytes: Bytes) -> Bytes

        /// ID of the entity
        func getID() -> Identifier

        /// Key of the entity. May be overridden for a custom key layout.
        func getIDAsKey() -> Bytes

        // MARK: Hooks

        /// System routines after loading, used by the entity extensions (e.g. indices). Don't implement it.
        func afterLoad0(within transaction: borrowing FDB.Transaction) async throws
        /// Custom routines after loading
        func afterLoad(within transaction: borrowing FDB.Transaction) async throws

        /// System routines before inserting, used by the entity extensions. Don't implement it.
        func beforeInsert0(within transaction: borrowing FDB.Transaction) async throws
        /// Custom routines before inserting
        func beforeInsert(within transaction: borrowing FDB.Transaction) async throws
        /// System routines after inserting, used by the entity extensions. Don't implement it.
        func afterInsert0(within transaction: borrowing FDB.Transaction) async throws
        /// Custom routines after inserting
        func afterInsert(within transaction: borrowing FDB.Transaction) async throws

        /// System routines before saving, used by the entity extensions. Don't implement it.
        func beforeSave0(within transaction: borrowing FDB.Transaction) async throws
        /// Custom routines before saving
        func beforeSave(within transaction: borrowing FDB.Transaction) async throws
        /// System routines after saving, used by the entity extensions. Don't implement it.
        func afterSave0(within transaction: borrowing FDB.Transaction) async throws
        /// Custom routines after saving
        func afterSave(within transaction: borrowing FDB.Transaction) async throws

        /// System routines before deleting, used by the entity extensions. Don't implement it.
        func beforeDelete0(within transaction: borrowing FDB.Transaction) async throws
        /// Custom routines before deleting
        func beforeDelete(within transaction: borrowing FDB.Transaction) async throws
        /// System routines after deleting, used by the entity extensions. Don't implement it.
        func afterDelete0(within transaction: borrowing FDB.Transaction) async throws
        /// Custom routines after deleting
        func afterDelete(within transaction: borrowing FDB.Transaction) async throws
    }

    /// Serialization format of entities
    public enum EntityFormat: String, CaseIterable, Sendable {
        case JSON, MsgPack
    }

    /// Errors of entities (FoundationDB errors are thrown as ``FDB/Error``)
    public enum EntityError: Swift.Error, Sendable, Equatable {
        /// The entity couldn't be serialized
        case serializationFailed(String)
        /// An entity with the same ID already exists (on insert)
        case alreadyExists(String)
        /// The entity doesn't exist
        case notFound(String)
        /// Another entity already has the same value of a unique index
        case uniqueIndexViolation(String)
        /// An index is not defined or is misused
        case invalidIndex(String)
    }
}

// MARK: - Defaults

public extension FDB.Entity {
    static var format: FDB.EntityFormat {
        .JSON
    }

    static var fullEntityName: Bool {
        false
    }

    static var entityName: String {
        let components = String(reflecting: Self.self).split(separator: ".")
        return components[(Self.fullEntityName ? 1 : components.count - 1)...].joined(separator: ".")
    }

    /// Subspace of entities of this type: `subspace/entityName`
    static var subspacePrefix: FDB.Subspace {
        Self.subspace[Self.entityName]
    }

    static func IDAsKey(ID: Identifier) -> Bytes {
        Self.subspacePrefix[ID].prefix
    }

    static func IDBytesAsKey(bytes: Bytes) -> Bytes {
        Self.subspacePrefix[bytes].prefix
    }

    func getID() -> Identifier {
        self[keyPath: Self.IDKey]
    }

    func getIDAsKey() -> Bytes {
        Self.IDAsKey(ID: self.getID())
    }

    func afterLoad0(within _: borrowing FDB.Transaction) async throws {}
    func afterLoad(within _: borrowing FDB.Transaction) async throws {}
    func beforeInsert0(within _: borrowing FDB.Transaction) async throws {}
    func beforeInsert(within _: borrowing FDB.Transaction) async throws {}
    func afterInsert0(within _: borrowing FDB.Transaction) async throws {}
    func afterInsert(within _: borrowing FDB.Transaction) async throws {}
    func beforeSave0(within _: borrowing FDB.Transaction) async throws {}
    func beforeSave(within _: borrowing FDB.Transaction) async throws {}
    func afterSave0(within _: borrowing FDB.Transaction) async throws {}
    func afterSave(within _: borrowing FDB.Transaction) async throws {}
    func beforeDelete0(within _: borrowing FDB.Transaction) async throws {}
    func beforeDelete(within _: borrowing FDB.Transaction) async throws {}
    func afterDelete0(within _: borrowing FDB.Transaction) async throws {}
    func afterDelete(within _: borrowing FDB.Transaction) async throws {}
}

// MARK: - Serialization

public extension FDB.Entity {
    /// Deserializes an entity
    init(from bytes: Bytes, format: FDB.EntityFormat = Self.format) throws {
        switch format {
        case .JSON: self = try JSONDecoder().decode(Self.self, from: Data(bytes))
        case .MsgPack: self = try MessagePackDecoder().decode(Self.self, from: Data(bytes))
        }
    }

    /// Serializes the entity
    func pack(to format: FDB.EntityFormat = Self.format) throws -> Bytes {
        do {
            switch format {
            case .JSON: return try Bytes(JSONEncoder().encode(self))
            case .MsgPack: return try Bytes(MessagePackEncoder().encode(self))
            }
        } catch {
            throw FDB.EntityError.serializationFailed("Could not serialize entity '\(Self.entityName)': \(error)")
        }
    }
}
