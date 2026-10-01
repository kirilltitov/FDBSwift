@testable import FDB
import Foundation
import Synchronization
import Testing

/// Integration tests, require a running FoundationDB cluster (default cluster file)
@Suite("Database")
struct DatabaseTests {
    static let db: FDB.Database = try! FDB.Database()

    let db = Self.db
    /// Every test works in its own subspace, so tests can run in parallel
    let subspace = FDB.Subspace("fdbswift-tests", UUID())

    @Test func setGetClear() async throws {
        let key = self.subspace["key"]
        #expect(try await self.db.get(key: key) == nil)

        try await self.db.set(key: key, value: [1, 2, 3])
        #expect(try await self.db.get(key: key) == [1, 2, 3])

        try await self.db.set(key: key, value: [])
        #expect(try await self.db.get(key: key) == [])

        try await self.db.clear(key: key)
        #expect(try await self.db.get(key: key) == nil)
    }

    @Test func keyTypes() async throws {
        let raw: Bytes = self.subspace.prefix + Bytes("raw".utf8)
        let string = String(decoding: self.subspace.prefix, as: UTF8.self) + "string"
        try await self.db.withTransaction { tr in
            tr.set(key: raw, value: [1])
            tr.set(key: self.subspace["tuple", 1], value: [2])
            tr.set(key: FDB.Tuple("fdbswift-tests-string", string), value: [3])
        }
        #expect(try await self.db.get(key: raw) == [1])
        #expect(try await self.db.get(key: self.subspace.subspace(FDB.Tuple("tuple", 1))) == [2])
        #expect(try await self.db.get(key: FDB.Tuple("fdbswift-tests-string", string)) == [3])
        try await self.db.clear(key: FDB.Tuple("fdbswift-tests-string", string))
    }

    @Test func parallelReadsInTransaction() async throws {
        try await self.db.withTransaction { tr in
            for i in 0 ..< 10 {
                tr.set(key: self.subspace[i], value: [UInt8(i)])
            }
        }
        let values = try await self.db.withTransaction { tr in
            // All requests are in flight before the first one is awaited
            let a = tr.get(key: self.subspace[1])
            let b = tr.get(key: self.subspace[2])
            let c = tr.get(key: self.subspace[42])
            return try await (a.value, b.value, c.value)
        }
        #expect(values.0 == [1])
        #expect(values.1 == [2])
        #expect(values.2 == nil)
    }

    @Test func getAllFetchesAllBatches() async throws {
        let count = 1000
        let value = Bytes(repeating: 0x42, count: 1024)
        // A key right before the range, must never leak into results
        try await self.db.set(key: self.subspace.prefix, value: value)
        try await self.db.withTransaction { tr in
            for i in 0 ..< count {
                tr.set(key: self.subspace[i], value: value)
            }
        }

        let all = try await self.db.getAll(self.subspace.range)
        #expect(all.count == count)
        #expect(all.first?.key == self.subspace[0].fdbKey)
        #expect(all.last?.key == self.subspace[count - 1].fdbKey)

        let limited = try await self.db.getAll(self.subspace.range, limit: 10)
        #expect(limited.map(\.key) == (0 ..< 10).map { self.subspace[$0].fdbKey })

        let reversed = try await self.db.getAll(self.subspace.range, limit: 3, reverse: true)
        #expect(reversed.map(\.key) == [999, 998, 997].map { self.subspace[$0].fdbKey })

        let single = try await self.db.withTransaction { tr in
            try await tr.getRange(
                begin: .firstGreaterOrEqual(self.subspace.range.begin),
                end: .firstGreaterOrEqual(self.subspace.range.end),
                limit: 5,
                mode: .exact
            ).value
        }
        #expect(single.records.count == 5)
        #expect(single.hasMore)

        try await self.db.clear(range: self.subspace.range)
        #expect(try await self.db.getAll(self.subspace.range).isEmpty)
        try await self.db.clear(key: self.subspace.prefix)
    }

    @Test func forEachBatchWithoutCopying() async throws {
        let count = 500
        try await self.db.withTransaction { tr in
            for i in 0 ..< count {
                tr.set(key: self.subspace[i], value: Bytes(repeating: UInt8(i % 256), count: 512))
            }
        }

        let (batches, records, checksum) = try await self.db.withTransaction { tr in
            var batches = 0
            var records = 0
            var checksum = 0
            try await tr.forEachBatch(in: self.subspace.range) { batch in
                batches += 1
                records += batch.count
                batch.forEach { _, value in
                    checksum += Int(value[0])
                }
            }
            return (batches, records, checksum)
        }
        #expect(batches > 1)
        #expect(records == count)
        #expect(checksum == (0 ..< count).reduce(0) { $0 + $1 % 256 })

        struct Stop: Error {}
        await #expect(throws: FDB.RangeError<Stop>.self) {
            try await self.db.withTransaction { tr in
                try await tr.forEachBatch(in: self.subspace.range) { (_: borrowing FDB.KeyValueBatch) throws(Stop) in
                    throw Stop()
                }
            }
        }
    }

    @Test func conflictIsRetried() async throws {
        let key = self.subspace["conflict"]
        try await self.db.set(key: key, value: [0])

        let attempts = Atomic<Int>(0)
        try await self.db.withTransaction { tr in
            let attempt = attempts.add(1, ordering: .relaxed).newValue
            let value = try await tr.get(key: key).value!
            if attempt == 1 {
                // Concurrent write to the key we've just read makes our commit conflict
                try await self.db.set(key: key, value: [42])
            }
            tr.set(key: key, value: [value[0] + 1])
        }
        #expect(attempts.load(ordering: .relaxed) == 2)
        #expect(try await self.db.get(key: key) == [43])
    }

    @Test func wrappedErrorsAreRetried() async throws {
        let attempts = Atomic<Int>(0)
        try await self.db.withTransaction { _ in
            if attempts.add(1, ordering: .relaxed).newValue == 1 {
                // What `forEachBatch` throws if a range read fails with a retryable error
                throw FDB.RangeError<Never>.fdb(.transactionTooOld)
            }
        }
        #expect(attempts.load(ordering: .relaxed) == 2)
    }

    @Test func retryLimit() async throws {
        let db = try FDB.Database(transactionRetryLimit: 2)
        let key = self.subspace["retry-limit"]
        try await db.set(key: key, value: [0])

        let attempts = Atomic<Int>(0)
        await #expect(throws: FDB.Error.notCommitted) {
            try await db.withTransaction { tr in
                attempts.add(1, ordering: .relaxed)
                _ = try await tr.get(key: key).value
                try await db.set(key: key, value: [UInt8(attempts.load(ordering: .relaxed))])
                tr.set(key: key, value: [0])
            }
        }
        #expect(attempts.load(ordering: .relaxed) == 3)
    }

    @Test func nonRetryableErrors() async throws {
        let attempts = Atomic<Int>(0)
        await #expect(throws: FDB.Error.keyTooLarge) {
            try await self.db.withTransaction { tr in
                attempts.add(1, ordering: .relaxed)
                // Fails on commit
                tr.set(key: Bytes(repeating: 1, count: 200_000), value: [])
            }
        }
        #expect(attempts.load(ordering: .relaxed) == 1)

        struct Custom: Error {}
        await #expect(throws: Custom.self) {
            try await self.db.withTransaction { _ in
                attempts.add(1, ordering: .relaxed)
                throw Custom()
            }
        }
        #expect(attempts.load(ordering: .relaxed) == 2)
    }

    @Test func cancellation() async throws {
        let version = try await self.db.withTransaction { tr in try await tr.getReadVersion().value }
        let task = Task {
            try await self.db.withTransaction { tr in
                // Reading at a version far in the future blocks until FDB gives up with `futureVersion`
                tr.setReadVersion(version + 1_000_000_000)
                return try await tr.get(key: self.subspace["cancel"]).value
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: FDB.Error.operationCancelled) {
            try await task.value
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func atomicOperations() async throws {
        let key = self.subspace["counter"]
        try await withThrowingTaskGroup { group in
            for _ in 0 ..< 10 {
                group.addTask { try await self.db.increment(key: key, by: 2) }
            }
            try await group.waitForAll()
        }
        let value = try #require(try await self.db.get(key: key))
        #expect(value.withUnsafeBytes { Int64(littleEndian: $0.loadUnaligned(as: Int64.self)) } == 20)

        try await self.db.withTransaction { tr in
            tr.atomic(.max, key: key, value: Int64(100))
        }
        #expect(try await self.db.get(key: key) == withUnsafeBytes(of: Int64(100).littleEndian) { Bytes($0) })
    }

    @Test func versionstampedKey() async throws {
        let subspace = self.subspace["versionstamped"]
        let (_, first) = try await self.db.withVersionstampedTransaction { tr in
            try tr.set(versionstampedKey: subspace[FDB.Versionstamp(userVersion: 1), "a"], value: [1])
            try tr.set(versionstampedKey: subspace[FDB.Versionstamp(userVersion: 2), "b"], value: [2])
        }
        let (_, second) = try await self.db.withVersionstampedTransaction { tr in
            try tr.set(versionstampedKey: subspace[FDB.Versionstamp(userVersion: 0), "c"], value: [3])
        }
        #expect(first.isComplete)
        #expect(second.transactionCommitVersion > first.transactionCommitVersion)

        #expect(try await self.db.get(key: subspace[first.with(userVersion: 1), "a"]) == [1])
        #expect(try await self.db.get(key: subspace[first.with(userVersion: 2), "b"]) == [2])
        #expect(try await self.db.get(key: subspace[second.with(userVersion: 0), "c"]) == [3])

        let keys = try await self.db.getAll(subspace.range).map { try subspace.unpack($0.key) }
        #expect(try keys.map { try $0.unpack(as: FDB.Versionstamp.self, String.self).1 } == ["a", "b", "c"])

        await #expect(throws: FDB.Error.missingIncompleteVersionstamp) {
            try await self.db.withTransaction { tr in
                try tr.set(versionstampedKey: subspace["no versionstamp"], value: [])
            }
        }
    }

    @Test func transactionOptions() async throws {
        try await self.db.withTransaction { tr in
            try tr.setOption(.timeout(milliseconds: 5000))
            try tr.setOption(.priorityBatch)
            try tr.setOption(.tag("fdbswift"))
            _ = try await tr.getReadVersion().value
            #expect(try await tr.getApproximateSize().value >= 0)
        }
    }

    @Test func network() throws {
        #expect(FDB.Network.isRunning)
        #expect(throws: FDB.Error.networkAlreadySetup) {
            try FDB.Network.setOption(.traceLogGroup("too late"))
        }
        // Network is started once, any number of databases can be opened
        _ = try FDB.Database()
        _ = try FDB.Database(connectionString: String(contentsOfFile: "/etc/foundationdb/fdb.cluster", encoding: .utf8))
    }

    @Test func errors() {
        #expect(FDB.Error.notCommitted.isRetryable)
        #expect(FDB.Error.notCommitted.isRetryableNotCommitted)
        #expect(FDB.Error.commitUnknownResult.isMaybeCommitted)
        #expect(!FDB.Error.keyTooLarge.isRetryable)
        #expect(!FDB.Error.unpackInvalidInput.isNative)
        #expect(FDB.Error.notCommitted.message == "Transaction not committed due to conflict with another transaction")
        #expect(FDB.Error.tagThrottled.message == "Transaction tag is being throttled")
        #expect(FDB.Error.batchTransactionThrottled.message == "Batch GRV request rate limit exceeded")
        #expect(FDB.Error.proxyMemoryLimitExceeded.message.contains("memory"))
        #expect(FDB.Error(code: 31337).message == "An unknown error occurred")
    }

    @Test func networkOptionRedaction() {
        #expect(FDB.NetworkOption.tlsKeyBytes(Bytes("SECRET".utf8)).redactedDescription == "tlsKeyBytes(<private>)")
        #expect(FDB.NetworkOption.tlsPassword("SECRET").redactedDescription == "tlsPassword(<private>)")
        #expect(FDB.NetworkOption.tlsCABytes([1, 2, 3]).redactedDescription == "tlsCABytes(<3 bytes>)")
        #expect(FDB.NetworkOption.traceLogGroup("foo").redactedDescription == #"traceLogGroup("foo")"#)
    }
}
