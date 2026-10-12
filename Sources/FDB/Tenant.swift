import CFDB

extension FDB {
    /// A tenant: a named, isolated key space within a cluster.
    ///
    /// Transactions created from a tenant see only the keys of that tenant: FoundationDB transparently prefixes
    /// them, so the same key in two tenants is two different keys, and a tenant transaction can't reach keys outside
    /// of its tenant (including system keys). Use it exactly like a ``FDB/Database``:
    ///
    /// ```swift
    /// try await db.createTenant("acme")
    /// let acme = try db.openTenant("acme")
    /// try await acme.withTransaction { tr in
    ///     tr.set(key: FDB.Tuple("users", 1), value: ...)
    /// }
    /// ```
    ///
    /// Requires the cluster to be configured with tenants enabled
    /// (`configure tenant_mode=optional_experimental` or `required_experimental`), otherwise transactions fail
    /// with ``FDB/Error/tenantsDisabled``. Opening a tenant doesn't check that it exists: transactions of
    /// a missing tenant fail with ``FDB/Error/tenantNotFound``.
    ///
    /// Requires API version 710 (see ``FDB/Network/selectAPIVersion(_:)``).
    public final class Tenant: Transactor {
        nonisolated(unsafe) let pointer: OpaquePointer
        /// Name of the tenant
        public let name: Bytes
        /// Database the tenant belongs to
        public let database: Database

        init(database: Database, name: Bytes) throws(FDB.Error) {
            try FDB.requireAPIVersion(710)
            var pointer: OpaquePointer?
            try fdb_database_open_tenant(database.pointer, name, Int32(name.count), &pointer).check()
            self.pointer = pointer!
            self.name = name
            self.database = database
        }

        deinit {
            fdb_tenant_destroy(self.pointer)
        }

        public func makeTransaction() throws(FDB.Error) -> Transaction {
            var pointer: OpaquePointer?
            try fdb_tenant_create_transaction(self.pointer, &pointer).check()
            return Transaction(pointer!, owner: self, logger: self.database.logger)
        }

        /// Returns the internal ID of the tenant (fails with ``FDB/Error/tenantNotFound`` if it doesn't exist)
        ///
        /// Requires API version 730.
        public func getID() throws(FDB.Error) -> Future<Int64> {
            try FDB.requireAPIVersion(730)
            return .int64(fdb_tenant_get_id(self.pointer))
        }
    }

    /// A tenant as listed by ``FDB/Database/listTenants(from:to:limit:)``
    public struct TenantInfo: Hashable, Sendable {
        /// Name of the tenant
        public let name: Bytes
        /// Tenant metadata as stored by FoundationDB: a JSON object with the tenant `id`, `prefix` etc.
        public let metadata: Bytes
    }
}

// MARK: - Opening tenants

extension FDB.Database {
    /// Opens a tenant with given name. Doesn't check that the tenant exists.
    public func openTenant(_ name: Bytes) throws(FDB.Error) -> FDB.Tenant {
        try FDB.Tenant(database: self, name: name)
    }

    /// Opens a tenant with given name. Doesn't check that the tenant exists.
    public func openTenant(_ name: String) throws(FDB.Error) -> FDB.Tenant {
        try self.openTenant(Bytes(name.utf8))
    }
}

// MARK: - Tenant management

/// Tenant management API: tenants are managed through the special key space, like in other bindings
extension FDB {
    static let tenantMapPrefix: Bytes = [0xFF, 0xFF] + Bytes("/management/tenant/map/".utf8)
}

extension FDB.Database {
    /// Creates a tenant, throws ``FDB/Error/tenantAlreadyExists`` if it exists
    ///
    /// The existence is checked only on the first attempt, so if the transaction is retried after an unknown
    /// commit result, it succeeds even if it was the first attempt which actually created the tenant.
    public func createTenant(_ name: Bytes) async throws {
        var checked = false
        try await self.withTransaction { tr in
            if !checked {
                let exists = try await tr.tenantExists(name)
                checked = true
                if exists {
                    throw FDB.Error.tenantAlreadyExists
                }
            }
            try tr.createTenant(name)
        }
    }

    /// Creates a tenant, throws ``FDB/Error/tenantAlreadyExists`` if it exists
    public func createTenant(_ name: String) async throws {
        try await self.createTenant(Bytes(name.utf8))
    }

    /// Deletes a tenant, throws ``FDB/Error/tenantNotFound`` if it doesn't exist and ``FDB/Error/tenantNotEmpty``
    /// if it contains any keys.
    ///
    /// The existence is checked only on the first attempt, see ``createTenant(_:)-(Bytes)``.
    public func deleteTenant(_ name: Bytes) async throws {
        var checked = false
        try await self.withTransaction { tr in
            if !checked {
                let exists = try await tr.tenantExists(name)
                checked = true
                if !exists {
                    throw FDB.Error.tenantNotFound
                }
            }
            try tr.deleteTenant(name)
        }
    }

    /// Deletes a tenant, see ``deleteTenant(_:)-(Bytes)``
    public func deleteTenant(_ name: String) async throws {
        try await self.deleteTenant(Bytes(name.utf8))
    }

    /// Lists tenants with names in given range
    ///
    /// - parameters:
    ///   - limit: Maximum number of tenants, 0 means no limit
    public func listTenants(from begin: Bytes = [], to end: Bytes = [0xFF], limit: Int = 0) async throws -> [FDB.TenantInfo] {
        try await self.withTransaction { tr in
            try await tr.listTenants(from: begin, to: end, limit: limit)
        }
    }
}

extension FDB.Transaction {
    /// Creates a tenant within this transaction.
    ///
    /// Doesn't check whether the tenant exists, use ``tenantExists(_:)`` for that if needed.
    public func createTenant(_ name: Bytes) throws(FDB.Error) {
        try self.setOption(.specialKeySpaceEnableWrites)
        self.set(key: FDB.tenantMapPrefix + name, value: [])
    }

    /// Deletes a tenant within this transaction.
    ///
    /// Doesn't check whether the tenant exists, use ``tenantExists(_:)`` for that if needed.
    public func deleteTenant(_ name: Bytes) throws(FDB.Error) {
        try self.setOption(.specialKeySpaceEnableWrites)
        self.clear(key: FDB.tenantMapPrefix + name)
    }

    /// Whether a tenant with given name exists
    public func tenantExists(_ name: Bytes) async throws(FDB.Error) -> Bool {
        try self.setOption(.specialKeySpaceEnableWrites)
        return try await self.get(key: FDB.tenantMapPrefix + name).value != nil
    }

    /// Lists tenants with names in given range, see ``FDB/Database/listTenants(from:to:limit:)``
    public func listTenants(from begin: Bytes = [], to end: Bytes = [0xFF], limit: Int = 0) async throws(FDB.Error) -> [FDB.TenantInfo] {
        try self.setOption(.rawAccess)
        let records = try await self.getAll(
            FDB.KeyRange(begin: FDB.tenantMapPrefix + begin, end: FDB.tenantMapPrefix + end),
            limit: limit
        )
        return records.map { record in
            FDB.TenantInfo(name: Bytes(record.key.dropFirst(FDB.tenantMapPrefix.count)), metadata: record.value)
        }
    }
}
