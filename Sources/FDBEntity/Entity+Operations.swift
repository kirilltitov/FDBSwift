public import FDB

// MARK: - Operations within a transaction

public extension FDB.Entity {
    /// Loads the entity with given ID
    static func load(
        by ID: Identifier,
        within transaction: borrowing FDB.Transaction,
        snapshot: Bool = false
    ) async throws -> Self? {
        try await Self.loadByRaw(key: Self.IDAsKey(ID: ID), within: transaction, snapshot: snapshot)
    }

    /// Loads the entity stored at given key (as returned by ``FDB/Entity/getIDAsKey()``)
    static func loadByRaw(
        key: Bytes,
        within transaction: borrowing FDB.Transaction,
        snapshot: Bool = false
    ) async throws -> Self? {
        guard let bytes = try await transaction.get(key: key, snapshot: snapshot).value else {
            return nil
        }
        return try await Self.decodeLoaded(bytes, within: transaction)
    }

    /// Whether the entity with given ID exists
    static func exists(by ID: Identifier, within transaction: borrowing FDB.Transaction) async throws -> Bool {
        try await transaction.get(key: Self.IDAsKey(ID: ID)).value != nil
    }

    /// Loads all entities stored in given subspace (all entities of this type by default)
    ///
    /// - parameters:
    ///   - limit: Maximum number of entities, 0 means no limit
    static func loadAll(
        in subspace: FDB.Subspace = Self.subspacePrefix,
        limit: Int = 0,
        within transaction: borrowing FDB.Transaction,
        snapshot: Bool = false
    ) async throws -> [Self] {
        var result: [Self] = []
        for record in try await transaction.getAll(subspace.range, limit: limit, snapshot: snapshot) {
            result.append(try await Self.decodeLoaded(record.value, within: transaction))
        }
        return result
    }

    /// Inserts the entity, throws ``FDB/EntityError/alreadyExists(_:)`` if an entity with the same key exists
    func insert(within transaction: borrowing FDB.Transaction) async throws {
        let key = self.getIDAsKey()
        guard try await transaction.get(key: key).value == nil else {
            throw FDB.EntityError.alreadyExists("Entity '\(Self.entityName)' with ID '\(self.getID())' already exists")
        }

        try await self.beforeInsert0(within: transaction)
        try await self.beforeInsert(within: transaction)
        transaction.set(key: key, value: try self.pack())
        try await self.afterInsert0(within: transaction)
        try await self.afterInsert(within: transaction)
    }

    /// Saves the entity, inserting or overwriting it
    func save(within transaction: borrowing FDB.Transaction) async throws {
        try await self.beforeSave0(within: transaction)
        try await self.beforeSave(within: transaction)
        transaction.set(key: self.getIDAsKey(), value: try self.pack())
        try await self.afterSave0(within: transaction)
        try await self.afterSave(within: transaction)
    }

    /// Deletes the entity
    func delete(within transaction: borrowing FDB.Transaction) async throws {
        try await self.beforeDelete0(within: transaction)
        try await self.beforeDelete(within: transaction)
        transaction.clear(key: self.getIDAsKey())
        try await self.afterDelete0(within: transaction)
        try await self.afterDelete(within: transaction)
    }

    /// Deserializes a loaded entity and runs `afterLoad` hooks
    static func decodeLoaded(_ bytes: Bytes, within transaction: borrowing FDB.Transaction) async throws -> Self {
        let entity = try Self(from: bytes, format: Self.format)
        try await entity.afterLoad0(within: transaction)
        try await entity.afterLoad(within: transaction)
        return entity
    }
}

// MARK: - Operations in their own transactions

public extension FDB.Entity {
    /// Loads the entity with given ID in a separate transaction
    static func load(by ID: Identifier, snapshot: Bool = false) async throws -> Self? {
        try await Self.storage.withTransaction { tr in try await Self.load(by: ID, within: tr, snapshot: snapshot) }
    }

    /// Whether the entity with given ID exists (in a separate transaction)
    static func exists(by ID: Identifier) async throws -> Bool {
        try await Self.storage.withTransaction { tr in try await Self.exists(by: ID, within: tr) }
    }

    /// Loads all entities stored in given subspace in a separate transaction
    static func loadAll(
        in subspace: FDB.Subspace = Self.subspacePrefix,
        limit: Int = 0,
        snapshot: Bool = false
    ) async throws -> [Self] {
        try await Self.storage.withTransaction { tr in
            try await Self.loadAll(in: subspace, limit: limit, within: tr, snapshot: snapshot)
        }
    }

    /// Inserts the entity in a separate transaction, see ``insert(within:)``
    func insert() async throws {
        try await Self.storage.withTransaction { tr in try await self.insert(within: tr) }
    }

    /// Saves the entity in a separate transaction
    func save() async throws {
        try await Self.storage.withTransaction { tr in try await self.save(within: tr) }
    }

    /// Deletes the entity in a separate transaction
    func delete() async throws {
        try await Self.storage.withTransaction { tr in try await self.delete(within: tr) }
    }
}
