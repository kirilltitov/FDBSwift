public import FDB
import Logging

extension FDB {
    /// Names of indices of an entity, usually a `String` enum:
    ///
    /// ```swift
    /// enum IndexKey: String, FDB.EntityIndexKey {
    ///     case email, country
    /// }
    /// ```
    public protocol EntityIndexKey: Hashable, RawRepresentable, CaseIterable, Sendable where RawValue == String {}

    /// An index of an entity property
    public struct EntityIndex<Entity: FDB.IndexedEntity>: Sendable {
        /// Whether the indexed value is unique among all entities of the type
        public let unique: Bool
        private let path: any PartialKeyPath<Entity> & Sendable

        public init<Value: FDB.TuplePackable>(_ path: any KeyPath<Entity, Value> & Sendable, unique: Bool) {
            self.unique = unique
            self.path = path
        }

        /// Indexed value of given entity
        func value(_ entity: Entity) -> any FDB.TuplePackable {
            // Can't fail: the path leads to a tuple-packable value (see init)
            entity[keyPath: self.path] as! any FDB.TuplePackable
        }
    }

    /// An entity with indices: lookups by property values.
    ///
    /// ```swift
    /// struct User: FDB.IndexedEntity {
    ///     enum IndexKey: String, FDB.EntityIndexKey {
    ///         case email, country
    ///     }
    ///
    ///     static let indices: [IndexKey: FDB.EntityIndex<User>] = [
    ///         .email: FDB.EntityIndex(\.email, unique: true),
    ///         .country: FDB.EntityIndex(\.country, unique: false),
    ///     ]
    ///     // ...
    /// }
    ///
    /// let user = try await User.loadByIndex(key: .email, value: "kirill@example.com")
    /// let users = try await User.loadAllByIndex(key: .country, value: "RU")
    /// ```
    ///
    /// Indices are maintained on insert, save and delete within the same transaction. Unique indices are enforced:
    /// saving an entity with a value another entity already has throws ``FDB/EntityError/uniqueIndexViolation(_:)``.
    ///
    /// Key layout (compatible with Entita2FDB):
    /// - `subspace/"idx"/entityName/key/value` → entity key (unique indices);
    /// - `subspace/"idx"/entityName/key/value/ID` → entity key (non-unique indices);
    /// - `subspace/"idx"/entityName/"idx"/ID/key/value` → empty ("index of index": current indexed values of an
    ///   entity, used to update indices).
    public protocol IndexedEntity: Entity {
        associatedtype IndexKey: FDB.EntityIndexKey

        /// Indices of the entity
        static var indices: [IndexKey: FDB.EntityIndex<Self>] { get }
    }
}

private let logger = Logger(label: "FDBEntity")

// MARK: - Keys

public extension FDB.IndexedEntity {
    /// Subspace of all indices of this entity type
    static var indexSubspace: FDB.Subspace {
        Self.subspace["idx"][Self.entityName]
    }

    /// Subspace of current indexed values of the entity ("index of index")
    var indexIndexSubspace: FDB.Subspace {
        Self.indexSubspace["idx", self.getID()]
    }

    /// Subspace of index entries for given index value
    static func getGenericIndexSubspaceForIndex(key: IndexKey, value: any FDB.TuplePackable) -> FDB.Subspace {
        Self.indexSubspace[key.rawValue].subspace(FDB.Tuple(elements: [value]))
    }

    /// Key of the entry of a unique index for given value
    static func getIndexKeyForUniqueIndex(key: IndexKey, value: any FDB.TuplePackable) -> FDB.Subspace {
        Self.getGenericIndexSubspaceForIndex(key: key, value: value)
    }

    /// Key of the index entry of the entity for given index and value
    func getIndexKeyForIndex(_ index: FDB.EntityIndex<Self>, key: IndexKey, value: any FDB.TuplePackable) -> FDB.Subspace {
        let subspace = Self.getGenericIndexSubspaceForIndex(key: key, value: value)
        return index.unique ? subspace : subspace[self.getID()]
    }

    /// Key of the "index of index" entry of the entity for given index and value
    func getIndexIndexKeyForIndex(key: IndexKey, value: any FDB.TuplePackable) -> FDB.Subspace {
        self.indexIndexSubspace[key.rawValue].subspace(FDB.Tuple(elements: [value]))
    }
}

// MARK: - Maintenance

public extension FDB.IndexedEntity {
    func afterInsert0(within transaction: borrowing FDB.Transaction) async throws {
        for (key, index) in Self.indices {
            try await self.createIndex(key: key, index: index, within: transaction)
        }
    }

    func afterSave0(within transaction: borrowing FDB.Transaction) async throws {
        // Current indexed values, as of the last save
        var unchanged: Set<IndexKey> = []
        for record in try await transaction.getAll(self.indexIndexSubspace.range) {
            let elements = try self.indexIndexSubspace.unpack(record.key).elements
            guard
                elements.count == 2,
                case let .string(name) = elements[0],
                let key = IndexKey(rawValue: name),
                let index = Self.indices[key]
            else {
                // Not an index of this entity (e.g. a custom "index of index" entry)
                continue
            }
            let storedValue = elements[1]
            if FDB.Tuple(elements: [storedValue]).packed == FDB.Tuple(elements: [index.value(self)]).packed {
                unchanged.insert(key)
                continue
            }
            try await self.removeIndex(key: key, index: index, value: storedValue, within: transaction)
        }

        for (key, index) in Self.indices where !unchanged.contains(key) {
            try await self.createIndex(key: key, index: index, within: transaction)
        }
    }

    func beforeDelete0(within transaction: borrowing FDB.Transaction) async throws {
        guard let bytes = try await transaction.get(key: self.getIDAsKey()).value else {
            throw FDB.EntityError.notFound("Entity '\(Self.entityName)' with ID '\(self.getID())' doesn't exist")
        }
        // Indices of the stored entity (the current instance may be modified)
        let stored = try Self(from: bytes)
        for (key, index) in Self.indices {
            try await stored.removeIndex(key: key, index: index, value: index.value(stored), within: transaction)
        }
    }

    private func createIndex(
        key: IndexKey,
        index: FDB.EntityIndex<Self>,
        within transaction: borrowing FDB.Transaction
    ) async throws {
        let value = index.value(self)
        let indexKey = self.getIndexKeyForIndex(index, key: key, value: value)
        let entityKey = self.getIDAsKey()

        if index.unique {
            // Not a snapshot read: concurrent saves with the same value conflict
            if let owner = try await transaction.get(key: indexKey).value, owner != entityKey {
                throw FDB.EntityError.uniqueIndexViolation(
                    "Another '\(Self.entityName)' already has '\(key.rawValue)' = \(FDB.Tuple(elements: [value]))"
                )
            }
        }

        transaction.set(key: indexKey, value: entityKey)
        transaction.set(key: self.getIndexIndexKeyForIndex(key: key, value: value), value: [])
    }

    private func removeIndex(
        key: IndexKey,
        index: FDB.EntityIndex<Self>,
        value: any FDB.TuplePackable,
        within transaction: borrowing FDB.Transaction
    ) async throws {
        let indexKey = self.getIndexKeyForIndex(index, key: key, value: value)
        if index.unique {
            // The entry of a unique index may belong to another entity (e.g. after the value was taken over)
            if try await transaction.get(key: indexKey).value == self.getIDAsKey() {
                transaction.clear(key: indexKey)
            }
        } else {
            transaction.clear(key: indexKey)
        }
        transaction.clear(key: self.getIndexIndexKeyForIndex(key: key, value: value))
    }
}

// MARK: - Lookups

public extension FDB.IndexedEntity {
    /// Loads the entity with given value of a unique index
    static func loadByIndex(
        key: IndexKey,
        value: any FDB.TuplePackable,
        within transaction: borrowing FDB.Transaction,
        snapshot: Bool = false
    ) async throws -> Self? {
        try Self.index(key, unique: true)
        guard let entityKey = try await transaction.get(
            key: Self.getIndexKeyForUniqueIndex(key: key, value: value),
            snapshot: snapshot
        ).value else {
            return nil
        }
        return try await Self.loadByRaw(key: entityKey, within: transaction, snapshot: snapshot)
    }

    /// Whether an entity with given value of a unique index exists
    static func existsByIndex(
        key: IndexKey,
        value: any FDB.TuplePackable,
        within transaction: borrowing FDB.Transaction
    ) async throws -> Bool {
        try Self.index(key, unique: true)
        return try await transaction.get(key: Self.getIndexKeyForUniqueIndex(key: key, value: value)).value != nil
    }

    /// Loads all entities with given value of an index
    ///
    /// - parameters:
    ///   - limit: Maximum number of entities, 0 means no limit
    static func loadAllByIndex(
        key: IndexKey,
        value: any FDB.TuplePackable,
        limit: Int = 0,
        within transaction: borrowing FDB.Transaction,
        snapshot: Bool = false
    ) async throws -> [Self] {
        if try Self.index(key).unique {
            return try await Self.loadByIndex(key: key, value: value, within: transaction, snapshot: snapshot)
                .map { [$0] } ?? []
        }
        let range = Self.getGenericIndexSubspaceForIndex(key: key, value: value).range
        var result: [Self] = []
        for record in try await transaction.getAll(range, limit: limit, snapshot: snapshot) {
            if let entity = try await Self.loadByRaw(key: record.value, within: transaction, snapshot: snapshot) {
                result.append(entity)
            } else {
                logger.warning("Index '\(key.rawValue)' of '\(Self.entityName)' points to a missing entity")
            }
        }
        return result
    }

    /// Loads the entity with given value of a unique index in a separate transaction
    static func loadByIndex(key: IndexKey, value: any FDB.TuplePackable, snapshot: Bool = false) async throws -> Self? {
        try await Self.storage.withTransaction { tr in
            try await Self.loadByIndex(key: key, value: value, within: tr, snapshot: snapshot)
        }
    }

    /// Whether an entity with given value of a unique index exists (in a separate transaction)
    static func existsByIndex(key: IndexKey, value: any FDB.TuplePackable) async throws -> Bool {
        try await Self.storage.withTransaction { tr in
            try await Self.existsByIndex(key: key, value: value, within: tr)
        }
    }

    /// Loads all entities with given value of an index in a separate transaction
    static func loadAllByIndex(
        key: IndexKey,
        value: any FDB.TuplePackable,
        limit: Int = 0,
        snapshot: Bool = false
    ) async throws -> [Self] {
        try await Self.storage.withTransaction { tr in
            try await Self.loadAllByIndex(key: key, value: value, limit: limit, within: tr, snapshot: snapshot)
        }
    }

    @discardableResult
    private static func index(_ key: IndexKey, unique: Bool? = nil) throws -> FDB.EntityIndex<Self> {
        guard let index = Self.indices[key] else {
            throw FDB.EntityError.invalidIndex("Index '\(key.rawValue)' is not defined in '\(Self.entityName)'")
        }
        if let unique, index.unique != unique {
            throw FDB.EntityError.invalidIndex(
                "Index '\(key.rawValue)' of '\(Self.entityName)' is \(index.unique ? "" : "not ")unique"
            )
        }
        return index
    }
}
