@testable import FDB
import Foundation
import Testing

/// Integration tests of tenants, require a running FoundationDB cluster with tenants enabled
/// (`configure tenant_mode=optional_experimental`)
@Suite("Tenants", .enabled(if: TestEnvironment.apiVersion >= 730, "Tenants require API 730"))
struct TenantTests {
    let db = DatabaseTests.db
    let name = Bytes("fdbswift-tests-\(UUID())".utf8)

    /// Runs the body with a fresh tenant, deleting it (with its contents) afterwards
    func withTenant(_ body: (FDB.Tenant) async throws -> Void) async throws {
        try await self.db.createTenant(self.name)
        let tenant = try self.db.openTenant(self.name)
        do {
            try await body(tenant)
        } catch {
            try? await self.cleanUp(tenant)
            throw error
        }
        try await self.cleanUp(tenant)
    }

    func cleanUp(_ tenant: FDB.Tenant) async throws {
        try await tenant.clear(range: FDB.KeyRange(begin: [], end: [0xFF]))
        try await self.db.deleteTenant(self.name)
    }

    @Test func isolation() async throws {
        try await self.withTenant { tenant in
            let key = FDB.Tuple("fdbswift-tests", "tenant-key", UUID())
            try await tenant.set(key: key, value: [1])
            #expect(try await tenant.get(key: key) == [1])
            // The same key outside of the tenant is a different key
            #expect(try await self.db.get(key: key) == nil)

            try await tenant.withTransaction { tr in
                let all = try await tr.getAll(FDB.KeyRange(begin: [], end: [0xFF]))
                #expect(all.map(\.key) == [key.packed])
            }
        }
    }

    @Test func management() async throws {
        try await self.withTenant { tenant in
            #expect(try await tenant.getID().value > 0)

            let listed = try await self.db.listTenants(from: self.name, to: self.name + [0x00])
            #expect(listed.map(\.name) == [self.name])
            #expect(String(decoding: listed[0].metadata, as: UTF8.self).contains("\"id\""))

            await #expect(throws: FDB.Error.tenantAlreadyExists) {
                try await self.db.createTenant(self.name)
            }

            try await tenant.set(key: [0x01], value: [])
            await #expect(throws: FDB.Error.tenantNotEmpty) {
                try await self.db.deleteTenant(self.name)
            }
        }

        await #expect(throws: FDB.Error.tenantNotFound) {
            try await self.db.deleteTenant(self.name)
        }
        await #expect(throws: FDB.Error.tenantNotFound) {
            try await self.db.openTenant(self.name).getID().value
        }
        #expect(try await self.db.listTenants(from: self.name, to: self.name + [0x00]).isEmpty)
    }

    @Test func directoriesInTenant() async throws {
        try await self.withTenant { tenant in
            let directory = try await FDB.DirectoryLayer.default.createOrOpen(["app"], in: tenant)
            try await tenant.set(key: try directory.subspace["key"], value: [42])
            #expect(try await FDB.DirectoryLayer.default.list(in: tenant) == ["app"])
            #expect(try await tenant.get(key: try directory.subspace["key"]) == [42])
            try await FDB.DirectoryLayer.default.remove(["app"], in: tenant)
            // Directory metadata lives in the tenant too
            try await tenant.clear(range: FDB.KeyRange(begin: [0xFE], end: [0xFF]))
        }
    }

    @Test func transactionLevelManagement() async throws {
        try await self.db.withTransaction { tr in
            #expect(try await !tr.tenantExists(self.name))
            try tr.createTenant(self.name)
        }
        #expect(try await self.db.withTransaction { tr in try await tr.tenantExists(self.name) })
        try await self.db.withTransaction { tr in try tr.deleteTenant(self.name) }
        #expect(try await self.db.withTransaction { tr in try await tr.tenantExists(self.name) } == false)
    }
}
