@testable import FDB
import Foundation
import Testing

/// Integration tests for watches, require a running FoundationDB cluster (default cluster file)
@Suite("Watches")
struct WatchTests {
    let db = DatabaseTests.db
    let subspace = FDB.Subspace("fdbswift-tests", UUID())

    @Test func watchOutlivesTransaction() async throws {
        let key = self.subspace["watched"]
        try await self.db.set(key: key, value: [0])

        // The watch is created inside the transaction and awaited after it's committed and gone
        let watch = try await self.db.withTransaction { tr in
            tr.watch(key: key)
        }
        try await Task.sleep(for: .milliseconds(100))
        let fired = watch.isReady
        #expect(!fired, "Watch must not fire without a change")

        try await self.db.set(key: key, value: [1])
        try await watch.value
    }

    @Test func waitForChange() async throws {
        let key = self.subspace["wait"]
        let waiter = Task { try await self.db.waitForChange(of: key) }
        try await Task.sleep(for: .milliseconds(200))
        try await self.db.set(key: key, value: [42])
        try await waiter.value
    }

    @Test func changesSequence() async throws {
        let key = self.subspace["changes"]
        var changes = self.db.changes(of: key).makeAsyncIterator()

        // Current value first
        #expect(try await changes.next() == .some(nil))

        try await self.db.set(key: key, value: [1])
        #expect(try await changes.next() == .some([1]))

        // The same value is never delivered twice in a row
        try await self.db.set(key: key, value: [1])
        try await self.db.set(key: key, value: [2])
        #expect(try await changes.next() == .some([2]))

        try await self.db.clear(key: key)
        #expect(try await changes.next() == .some(nil))
    }

    @Test func changesCancellation() async throws {
        let key = self.subspace["cancel"]
        let consumer = Task {
            var count = 0
            for try await _ in self.db.changes(of: key) {
                count += 1
            }
            return count
        }
        try await Task.sleep(for: .milliseconds(300))
        let start = ContinuousClock.now
        consumer.cancel()
        await #expect(throws: FDB.Error.operationCancelled) {
            try await consumer.value
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func tooManyWatches() async throws {
        let db = try TestEnvironment.makeDatabase()
        try db.setOption(.maxWatches(1))
        let key = self.subspace["too-many"]

        let first = try await db.withTransaction { tr in tr.watch(key: key) }
        let second = try await db.withTransaction { tr in tr.watch(key: key) }
        var thrown: FDB.Error?
        do {
            try await second.value
        } catch {
            thrown = error
        }
        #expect(thrown == .tooManyWatches)
        first.cancel()
    }
}
