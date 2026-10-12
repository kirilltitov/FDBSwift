@testable import FDB
import Foundation
import Testing

/// Integration tests of the directory layer, require a running FoundationDB cluster
@Suite("Directory layer")
struct DirectoryTests {
    let db = DatabaseTests.db
    let subspace = FDB.Subspace("fdbswift-tests", UUID())
    /// Every test uses its own directory layer, so tests can run in parallel
    let directoryLayer: FDB.DirectoryLayer

    init() {
        self.directoryLayer = FDB.DirectoryLayer(
            nodeSubspace: self.subspace["nodes"],
            contentSubspace: self.subspace["content"]
        )
    }

    @Test func createOpenAndList() async throws {
        let users = try await self.directoryLayer.createOrOpen(["app", "users"], in: self.db)
        #expect(users.path == ["app", "users"])
        #expect(users.layer == [])
        #expect(!users.isPartition)
        #expect(users.prefix.starts(with: self.subspace["content"].prefix))

        let opened = try await self.directoryLayer.open(["app", "users"], in: self.db)
        #expect(opened == users)
        #expect(try await self.directoryLayer.createOrOpen(["app", "users"], in: self.db) == users)

        let orders = try await self.directoryLayer.create(["app", "orders"], in: self.db)
        #expect(orders.prefix != users.prefix)

        #expect(try await self.directoryLayer.list(in: self.db) == ["app"])
        #expect(try await self.directoryLayer.list(["app"], in: self.db) == ["orders", "users"])
        #expect(try await self.directoryLayer.exists(["app", "users"], in: self.db))
        #expect(try await !self.directoryLayer.exists(["app", "nope"], in: self.db))

        await #expect(throws: FDB.Error.directoryAlreadyExists) {
            try await self.directoryLayer.create(["app", "users"], in: self.db)
        }
        await #expect(throws: FDB.Error.directoryDoesNotExist) {
            try await self.directoryLayer.open(["app", "nope"], in: self.db)
        }
        await #expect(throws: FDB.Error.directoryRootOperation) {
            try await self.directoryLayer.open([], in: self.db)
        }
    }

    @Test func contents() async throws {
        let users = try await self.directoryLayer.createOrOpen(["users"], in: self.db)
        try await self.db.withTransaction { tr in
            tr.set(key: try users.subspace["alice"], value: [1])
            tr.set(key: try users.subspace["bob"], value: [2])
        }
        let records = try await self.db.getAll(try users.subspace.range)
        #expect(records.map(\.value) == [[1], [2]])
    }

    @Test func relativeOperations() async throws {
        let app = try await self.directoryLayer.createOrOpen(["app"], in: self.db)
        try await self.db.withTransaction { tr in
            let users = try await app.createOrOpen(["users"], in: tr)
            #expect(users.path == ["app", "users"])
            #expect(try await app.list(in: tr) == ["users"])
            #expect(try await app.exists(["users"], in: tr))
            #expect(try await app.open(["users"], in: tr) == users)
        }
    }

    @Test func layers() async throws {
        let layer = Bytes("my-layer".utf8)
        let directory = try await self.directoryLayer.create(["layered"], layer: layer, in: self.db)
        #expect(directory.layer == layer)
        #expect(try await self.directoryLayer.open(["layered"], layer: layer, in: self.db) == directory)
        // An empty layer is not checked
        #expect(try await self.directoryLayer.open(["layered"], in: self.db) == directory)
        await #expect(throws: FDB.Error.directoryIncompatibleLayer) {
            try await self.directoryLayer.open(["layered"], layer: Bytes("other".utf8), in: self.db)
        }
    }

    @Test func move() async throws {
        let directory = try await self.directoryLayer.create(["a", "b"], in: self.db)
        try await self.db.set(key: try directory.subspace["key"], value: [42])

        await #expect(throws: FDB.Error.directoryParentDoesNotExist) {
            try await self.directoryLayer.move(["a", "b"], to: ["x", "y"], in: self.db)
        }
        await #expect(throws: FDB.Error.directoryMoveIntoSubdirectory) {
            try await self.directoryLayer.move(["a"], to: ["a", "b", "c"], in: self.db)
        }

        let moved = try await self.directoryLayer.move(["a", "b"], to: ["c"], in: self.db)
        #expect(moved.path == ["c"])
        #expect(moved.prefix == directory.prefix)
        #expect(try await self.db.get(key: try moved.subspace["key"]) == [42])
        #expect(try await !self.directoryLayer.exists(["a", "b"], in: self.db))
        #expect(try await self.directoryLayer.list(in: self.db) == ["a", "c"])

        let movedBack = try await self.db.withTransaction { tr in try await moved.move(to: ["a", "d"], in: tr) }
        #expect(movedBack.path == ["a", "d"])
    }

    @Test func remove() async throws {
        let parent = try await self.directoryLayer.create(["parent"], in: self.db)
        let child = try await self.directoryLayer.create(["parent", "child"], in: self.db)
        try await self.db.withTransaction { tr in
            tr.set(key: try parent.subspace["key"], value: [1])
            tr.set(key: try child.subspace["key"], value: [2])
        }

        try await self.directoryLayer.remove(["parent"], in: self.db)
        #expect(try await !self.directoryLayer.exists(["parent"], in: self.db))
        #expect(try await !self.directoryLayer.exists(["parent", "child"], in: self.db))
        #expect(try await self.db.get(key: try parent.subspace["key"]) == nil)
        #expect(try await self.db.get(key: try child.subspace["key"]) == nil)

        await #expect(throws: FDB.Error.directoryDoesNotExist) {
            try await self.directoryLayer.remove(["parent"], in: self.db)
        }
        #expect(try await !self.directoryLayer.removeIfExists(["parent"], in: self.db))
        await #expect(throws: FDB.Error.directoryRootOperation) {
            try await self.directoryLayer.remove([], in: self.db)
        }
    }

    @Test func partitions() async throws {
        let partition = try await self.directoryLayer.create(
            ["partition"], layer: FDB.DirectoryLayer.partitionLayer, in: self.db
        )
        #expect(partition.isPartition)
        #expect(throws: FDB.Error.directoryPartitionRoot) {
            try partition.subspace
        }

        let inner = try await self.directoryLayer.createOrOpen(["partition", "inner"], in: self.db)
        #expect(inner.path == ["partition", "inner"])
        #expect(inner.prefix.starts(with: partition.prefix))
        #expect(try await self.directoryLayer.list(["partition"], in: self.db) == ["inner"])

        let outer = try await self.directoryLayer.create(["outer"], in: self.db)
        await #expect(throws: FDB.Error.directoryMoveBetweenPartitions) {
            try await self.directoryLayer.move(["partition", "inner"], to: ["outer", "inner"], in: self.db)
        }
        _ = outer

        // The partition itself is managed by the parent directory layer
        try await self.db.withTransaction { tr in try await partition.remove(in: tr) }
        #expect(try await !self.directoryLayer.exists(["partition"], in: self.db))
    }

    @Test func manualPrefixes() async throws {
        await #expect(throws: FDB.Error.directoryManualPrefixesDisabled) {
            try await self.directoryLayer.create(["manual"], prefix: [0x01], in: self.db)
        }

        let manual = FDB.DirectoryLayer(
            nodeSubspace: self.subspace["manual-nodes"],
            contentSubspace: self.subspace["manual-content"],
            allowManualPrefixes: true
        )
        let prefix = self.subspace["manual-prefix"].prefix
        let directory = try await manual.create(["manual"], prefix: prefix, in: self.db)
        #expect(directory.prefix == prefix)
        await #expect(throws: FDB.Error.directoryPrefixInUse) {
            try await manual.create(["other"], prefix: prefix + [0x01], in: self.db)
        }
    }

    @Test func allocatedPrefixesAreUnique() async throws {
        let directories = try await withThrowingTaskGroup(of: FDB.DirectorySubspace.self) { group in
            for index in 0 ..< 50 {
                group.addTask {
                    try await self.directoryLayer.create(["dir\(index)"], in: self.db)
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(Set(directories.map(\.prefix)).count == 50)
    }
}
