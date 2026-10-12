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
        // A manually managed transaction must pass unrelated errors to `onError`, like `withTransaction` does:
        // e.g. the multi-version client reports `clusterVersionChanged` while it connects to an older cluster
        for attempt in 1 ... 10 {
            do {
                try tr.setOption(.reportConflictingKeys)
                _ = try await tr.get(key: key).value
                tr.set(key: other, value: [1])

                // A concurrent write to the key read by `tr`
                try await self.db.set(key: key, value: [UInt8(attempt)])

                try await tr.commit().value
                Issue.record("Commit must fail")
                return
            } catch let error as FDB.Error where error == .notCommitted {
                let conflicts = try await tr.getConflictingKeys()
                #expect(conflicts == [FDB.KeyRange(begin: key.prefix, end: key.prefix + [0x00])])
                return
            } catch let error as FDB.Error {
                try await tr.onError(error).value
            }
        }
        Issue.record("No conflict after 10 attempts")
    }

    @Test(.enabled(if: TestEnvironment.apiVersion >= 730)) func transactionCosts() async throws {
        try await self.db.withTransaction { tr in
            tr.set(key: self.subspace["key"], value: Bytes(repeating: 1, count: 100))
            let cost = try await tr.getTotalCost().value
            let throttled = try await tr.getTagThrottledDuration().value
            #expect(cost >= 0)
            #expect(throttled >= 0)
        }
    }

    @Test(.enabled(if: TestEnvironment.apiVersion >= 730)) func databaseInfo() async throws {
        let busyness = try self.db.mainThreadBusyness
        #expect(busyness >= 0 && busyness <= 1)

        let status = try await self.db.getClientStatus().value
        #expect(String(decoding: status, as: UTF8.self).hasPrefix("{"))

        #expect(try await self.db.getServerProtocol().value > 0)
    }

    @Test func featuresRequireAPIVersion() async throws {
        let apiVersion = FDB.apiVersion
        if apiVersion < 710 {
            #expect(throws: FDB.Error.unsupportedOperation) {
                try self.db.openTenant("tenant")
            }
        }
        if apiVersion < 700 {
            #expect(throws: FDB.Error.unsupportedOperation) {
                try self.db.mainThreadBusyness
            }
        }
        try await self.db.withTransaction { tr in
            if apiVersion < 730 {
                #expect(throws: FDB.Error.unsupportedOperation) {
                    _ = try tr.getTotalCost()
                }
            }
            if apiVersion < 700 {
                #expect(throws: FDB.Error.unsupportedOperation) {
                    _ = try tr.getRangeSplitPoints(self.subspace.range, chunkSize: 1000)
                }
            }
        }
    }

    @Test func selectingAPIVersionTooLate() {
        _ = self.db
        #expect(throws: FDB.Error.apiVersionAlreadySet) {
            try FDB.Network.selectAPIVersion(FDB.minimumAPIVersion)
        }
        #expect(throws: FDB.Error.apiVersionNotSupported) {
            try FDB.Network.selectAPIVersion(FDB.latestAPIVersion + 10)
        }
    }
}
