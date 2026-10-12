@testable import FDB
import Foundation
import Testing

/// Integration tests of locality, conflicting keys and cluster management calls
@Suite("Cluster")
struct ClusterTests {
    let db = DatabaseTests.db
    let subspace = FDB.Subspace("fdbswift-tests", UUID())

    @Test func addresses() async throws {
        let key = self.subspace["key"]
        let addresses = try await self.db.withTransaction { tr in
            try await tr.getAddresses(for: key).value
        }
        #expect(!addresses.isEmpty)
        for address in addresses {
            #expect(address.contains(":"))
        }
    }

    @Test func boundaryKeys() async throws {
        let keys = try await self.db.getBoundaryKeys(in: FDB.KeyRange(begin: [], end: [0xFF]))
        // A single-process cluster has at least one shard, starting at the beginning of the key space
        #expect(keys.first == [])
        #expect(keys == keys.sorted { $0.lexicographicallyPrecedes($1) })

        #expect(try await self.db.getBoundaryKeys(in: FDB.KeyRange(begin: [0x01], end: [0x01])).isEmpty)
    }

    @Test func conflictingKeys() async throws {
        let key = self.subspace["contended"]
        let other = self.subspace["other"]

        let tr = try self.db.makeTransaction()
        try tr.setOption(.reportConflictingKeys)
        _ = try await tr.get(key: key).value
        tr.set(key: other, value: [1])

        // A concurrent write to the key read by `tr`
        try await self.db.set(key: key, value: [2])

        do {
            try await tr.commit().value
            Issue.record("Commit must fail")
        } catch .notCommitted {
            let conflicts = try await tr.getConflictingKeys()
            #expect(conflicts == [FDB.KeyRange(begin: key.prefix, end: key.prefix + [0x00])])
        }
    }

    @Test func transactionCosts() async throws {
        try await self.db.withTransaction { tr in
            tr.set(key: self.subspace["key"], value: Bytes(repeating: 1, count: 100))
            let cost = try await tr.getTotalCost().value
            let throttled = try await tr.getTagThrottledDuration().value
            #expect(cost >= 0)
            #expect(throttled >= 0)
        }
    }

    @Test func databaseInfo() async throws {
        let busyness = self.db.mainThreadBusyness
        #expect(busyness >= 0 && busyness <= 1)

        let status = try await self.db.getClientStatus().value
        #expect(String(decoding: status, as: UTF8.self).hasPrefix("{"))

        #expect(try await self.db.getServerProtocol().value > 0)
    }
}
