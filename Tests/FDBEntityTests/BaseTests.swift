@testable import FDBEntity
import FDB
import Helpers
import LGNLog
import Foundation
import MessagePack
import XCTest

internal extension Bytes {
    var _string: String { String(bytes: self, encoding: .ascii)! }
}

final class BaseTests: XCTestCase {
    static let storage: FDBConnector = DummyStorage(clusterFile: nil, networkStopTimeout: 0)
    static let subspace: FDB.Subspace = .init("test")

    struct DummyStorage: FDBConnector {
        static var logger: Logging.Logger = .init(label: "test")

        struct DummyTransaction: FDBTransaction {
            func get(key: any FDBKey, snapshot: Bool) async throws -> Bytes? {
                let result: Bytes?

                print(key.getPackedFDBTupleValue()._string)
                print(key.asFDBKey()._string)

                print("TestEntity.sampleEntity.getIDAsKey(): \(TestEntity.sampleEntity.getIDAsKey()._string)")

                switch key.asFDBKey() {
                case TestEntity.sampleEntity.getIDAsKey(): // TestEntity
                    result = getBytes("""
                        {
                            "string": "foo",
                            "ints": [322, 1337],
                            "subEntity": {
                                "myValue": "sikes",
                                "customID": 1337
                            },
                            "mapOfBooleans": {
                                "kek": false,
                                "lul": true
                            },
                            "bool": true,
                            "float": 322.1337,
                            "ID": "NHtKl8JnQj+oR4gCRvxpcg=="
                        }
                    """)
                case TestEntity.sampleEntity.subEntity.getIDAsKey(): // TestEntity.SubEntity
                    result = getBytes("""
                        {
                            "myValue": "sikes",
                            "customID": 1337
                        }
                    """)
                case TestEntity.SubEntity2.sampleEntity.getIDAsKey():
                    result = getBytes("{\"ID\": \"4C428E9B-3EBC-4443-9C28-FC109141FF84\"}")
                case [0]: // invalid
                    result = [1, 3, 3, 7, 3, 2, 2]
                default:
                    result = nil
                }

                dump(result?.string)

                return result
            }

            func set(key: any FDBKey, value: Bytes) {}
            func destroy() {}
            func cancel() {}
            func reset() {}
            func clear(key: any FDBKey) {}
            func clear(begin: any FDBKey, end: any FDBKey) {}
            func clear(range: FDB.RangeKey) {}
            func atomic(_ op: FDB.MutationType, key: any FDBKey, value: Bytes) {}
            func atomic<T>(_ op: FDB.MutationType, key: any FDBKey, value: T) {}
            func setReadVersion(version: Int64) {}
            func getReadVersion() async throws -> Int64 { 0 }
            func getVersionstamp() async throws -> FDB.Versionstamp { throw FDB.Entity.Error.SaveError("noop") }
            func commit() async throws {}
        }

        init(clusterFile: String?, networkStopTimeout: Int) {}

        public func connect() throws {}
        public func disconnect() {}
        public func set(key: any FDBKey, value: Bytes) async throws {}
        public func clear(key: any FDBKey) async throws {}
        public func clear(begin: any FDBKey, end: any FDBKey) async throws {}
        public func clear(range: FDB.RangeKey) async throws {}
        public func clear(subspace: FDB.Subspace) async throws {}
        public func atomic(_ op: FDB.MutationType, key: any FDBKey, value: Bytes) async throws {}
        public func atomic<T>(_ op: FDB.MutationType, key: any FDBKey, value: T) async throws where T : SignedInteger {}

        public func begin() throws -> any FDBTransaction {
            DummyTransaction()
        }
    }

    final class TestEntity: FDBEntity, Equatable {
        struct SubEntity: FDBEntity, Equatable {
            typealias Identifier = Int

            static var subspace = BaseTests.subspace

            static var storage = BaseTests.storage
            static var fullEntityName: Bool = false
            static var format: FDB.Entity.Format = .JSON
            static var IDKey: KeyPath<SubEntity, Identifier> = \.customID
            static var sampleEntity: Self {
                Self(customID: 1337, myValue: "sikes")
            }

            var customID: Identifier
            var myValue: String
        }

        struct SubEntity2: FDBEntity, Equatable {
            typealias Identifier = UUID

            static var subspace = BaseTests.subspace

            static var storage = BaseTests.storage
            static var fullEntityName: Bool = false
            static var format: FDB.Entity.Format = .JSON
            static var IDKey: KeyPath<Self, Identifier> = \.ID
            static var sampleEntity: Self {
                Self(ID: UUID(uuidString: "4C428E9B-3EBC-4443-9C28-FC109141FF84")!)
            }

            var ID: Identifier
        }

        enum CodingKeys: String, CodingKey {
            case ID
            case string
            case ints
            case mapOfBooleans
            case float
            case bool
            case subEntity
        }

        typealias Identifier = FDB.UUID

        static var storage = BaseTests.storage
        static var subspace = BaseTests.subspace
        static var format: FDB.Entity.Format = .JSON
        static var IDKey: KeyPath<TestEntity, Identifier> = \.ID
        static var sampleEntity: TestEntity {
            TestEntity(
                ID: FDB.UUID("347b4a97-c267-423f-a847-880246fc6972")!,
                string: "foo",
                ints: [322, 1337],
                mapOfBooleans: ["lul": true, "kek": false],
                float: 322.1337,
                bool: true,
                subEntity: SubEntity.sampleEntity
            )
        }

        static func == (lhs: BaseTests.TestEntity, rhs: BaseTests.TestEntity) -> Bool {
            true
                && lhs.ID == rhs.ID
                && lhs.string == rhs.string
                && lhs.ints == rhs.ints
                && lhs.mapOfBooleans == rhs.mapOfBooleans
                && lhs.float == rhs.float
                && lhs.bool == rhs.bool
                && lhs.subEntity == rhs.subEntity
        }

        var didCallAfterLoad0: Bool = false
        var didCallAfterLoad: Bool = false
        var didCallBeforeSave0: Bool = false
        var didCallBeforeSave: Bool = false
        var didCallAfterSave0: Bool = false
        var didCallAfterSave: Bool = false
        var didCallBeforeInsert0: Bool = false
        var didCallBeforeInsert: Bool = false
        var didCallAfterInsert: Bool = false
        var didCallAfterInsert0: Bool = false
        var didCallBeforeDelete0: Bool = false
        var didCallBeforeDelete: Bool = false
        var didCallAfterDelete0: Bool = false
        var didCallAfterDelete: Bool = false

        public func afterLoad0(within _: any FDBTransaction) async throws {
            didCallAfterLoad0 = true
        }

        public func afterLoad(within _: any FDBTransaction) async throws {
            didCallAfterLoad = true
        }

        func beforeSave0(within _: any FDBTransaction) async throws {
            didCallBeforeSave0 = true
        }

        func beforeSave(within _: any FDBTransaction) async throws {
            didCallBeforeSave = true
        }

        func afterSave0(within _: any FDBTransaction) async throws {
            didCallAfterSave0 = true
        }

        func afterSave(within _: any FDBTransaction) async throws {
            didCallAfterSave = true
        }

        func beforeInsert0(within _: any FDBTransaction) async throws {
            didCallBeforeInsert0 = true
        }

        func beforeInsert(within _: any FDBTransaction) async throws {
            didCallBeforeInsert = true
        }

        func afterInsert(within _: any FDBTransaction) async throws {
            didCallAfterInsert = true
        }

        func afterInsert0(within _: any FDBTransaction) async throws {
            didCallAfterInsert0 = true
        }

        func beforeDelete0(within _: any FDBTransaction) async throws {
            didCallBeforeDelete0 = true
        }

        func beforeDelete(within _: any FDBTransaction) async throws {
            didCallBeforeDelete = true
        }

        func afterDelete0(within _: any FDBTransaction) async throws {
            didCallAfterDelete0 = true
        }

        func afterDelete(within _: any FDBTransaction) async throws {
            didCallAfterDelete = true
        }

        var ID: Identifier
        var string: String
        var ints: [Int]
        var mapOfBooleans: [String: Bool]
        var float: Float
        var bool: Bool
        var subEntity: SubEntity

        init(
            ID: Identifier,
            string: String,
            ints: [Int],
            mapOfBooleans: [String: Bool],
            float: Float,
            bool: Bool,
            subEntity: SubEntity
        ) {
            self.ID = ID
            self.string = string
            self.ints = ints
            self.mapOfBooleans = mapOfBooleans
            self.float = float
            self.bool = bool
            self.subEntity = subEntity
        }
    }

    struct InvalidPackEntity: FDBEntity {
        typealias Identifier = Int

        static var storage = BaseTests.storage
        static var subspace = BaseTests.subspace
        static var fullEntityName: Bool = false
        static var format: FDB.Entity.Format = .JSON
        static var IDKey: KeyPath<InvalidPackEntity, Identifier> = \.ID

        var ID: Identifier

        func pack(to _: FDB.Entity.Format = Self.format) throws -> Bytes {
            throw EncodingError.invalidValue(
                "test",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "error"
                )
            )
        }
    }

    func testFormats() throws {
        let sampleEntity = TestEntity.sampleEntity

        for format in FDB.Entity.Format.allCases {
            XCTAssertEqual(
                try TestEntity(from: sampleEntity.pack(to: format), format: format),
                sampleEntity
            )
        }
    }

    func testGetID() {
        let sampleEntity = TestEntity.sampleEntity
        let sampleSubEntity = sampleEntity.subEntity
        XCTAssertEqual(sampleEntity.getID(), sampleEntity.ID)
        XCTAssertEqual(sampleSubEntity.getID(), sampleSubEntity.customID)
    }

    func testIDBytes() {
        let sampleEntity = TestEntity.sampleEntity

        let sampleIDBytes = getBytes(sampleEntity.ID)
        let sampleCustomIDBytes = getBytes(sampleEntity.subEntity.customID)
        XCTAssertEqual(sampleEntity.ID._bytes, sampleIDBytes)
        XCTAssertEqual(sampleEntity.subEntity.customID._bytes, sampleCustomIDBytes)
    }

    func testUUIDID() async throws {
        let sampleEntity = TestEntity.SubEntity2.sampleEntity
        let loadedEntity = try await TestEntity.SubEntity2.load(by: UUID(uuidString: "4C428E9B-3EBC-4443-9C28-FC109141FF84")!)
        XCTAssertEqual(sampleEntity, loadedEntity)

        XCTAssertEqual(
            UUID(uuidString: "53D29EF7-377C-4D14-864B-EB3A85769359")!._bytes,
            UUID(uuidString: "53D29EF7-377C-4D14-864B-EB3A85769359")!._bytes
        )
    }

    func testEntityName() {
        XCTAssertEqual(TestEntity.entityName, "TestEntity")
        XCTAssertEqual(TestEntity.SubEntity.entityName, "SubEntity")
        TestEntity.SubEntity.fullEntityName = true
        XCTAssertEqual(TestEntity.SubEntity.entityName, "BaseTests.TestEntity.SubEntity")
        TestEntity.SubEntity.fullEntityName = false
    }

    func testGetPackedSelf() throws {
        _ = try TestEntity.sampleEntity.getPackedSelf()

        do {
            _ = try InvalidPackEntity(ID: 1).getPackedSelf()
            XCTFail("Should've thrown")
        } catch {}
    }

    func testLoad() async throws {
        let sampleEntity = TestEntity.sampleEntity

        let loaded = try await TestEntity.loadByRaw(IDBytes: sampleEntity.getIDAsKey())

        guard let loaded else {
            XCTFail("Did not load entity")
            return
        }

        XCTAssertEqual(loaded, sampleEntity)

        XCTAssertTrue(loaded.didCallAfterLoad)
        XCTAssertTrue(loaded.didCallAfterLoad0)

        let actual2 = try await TestEntity.load(by: sampleEntity.ID)
        XCTAssertEqual(actual2, sampleEntity)

        let actual3 = try await TestEntity.loadByRaw(IDBytes: [1, 2, 3])
        XCTAssertEqual(actual3, nil)

        do {
            _ = try await TestEntity.loadByRaw(IDBytes: [0])
            XCTFail("Should've thrown")
        } catch {}

        TestEntity.format = .MsgPack
        do {
            _ = try await TestEntity.loadByRaw(IDBytes: [0])
            XCTFail("Should've thrown")
        } catch {}

        TestEntity.format = .JSON
        let loadedSubEntity = try await TestEntity.SubEntity.loadByRaw(IDBytes: sampleEntity.subEntity.getIDAsKey())
        XCTAssertEqual(loadedSubEntity, sampleEntity.subEntity)
    }

    func testSave() async throws {
        let sampleEntity = TestEntity.sampleEntity
        let sampleSubEntity = TestEntity.sampleEntity.subEntity

        try await sampleEntity.save(commit: true)
        try await sampleSubEntity.save(commit: true)
        try await sampleEntity.save(by: sampleEntity.ID, commit: true)

        XCTAssertTrue(sampleEntity.didCallBeforeSave0)
        XCTAssertTrue(sampleEntity.didCallBeforeSave)
        XCTAssertTrue(sampleEntity.didCallAfterSave)
        XCTAssertTrue(sampleEntity.didCallAfterSave0)
    }

    func testInsert() async throws {
        let sampleEntity = TestEntity.sampleEntity
        let sampleSubEntity = TestEntity.sampleEntity.subEntity

        try await sampleEntity.insert(commit: true)
        try await sampleSubEntity.insert()

        let transaction = try Self.storage.begin()
        try await sampleEntity.insert(within: transaction, commit: true)

        XCTAssertTrue(sampleEntity.didCallBeforeInsert0)
        XCTAssertTrue(sampleEntity.didCallBeforeInsert)
        XCTAssertTrue(sampleEntity.didCallAfterInsert)
        XCTAssertTrue(sampleEntity.didCallAfterInsert0)
    }

    func testDelete() async throws {
        let sampleEntity = TestEntity.sampleEntity
        let sampleSubEntity = TestEntity.sampleEntity.subEntity

        try await sampleEntity.delete(commit: true)
        try await sampleSubEntity.delete(commit: false)

        XCTAssertTrue(sampleEntity.didCallBeforeDelete0)
        XCTAssertTrue(sampleEntity.didCallBeforeDelete)
        XCTAssertTrue(sampleEntity.didCallAfterDelete)
        XCTAssertTrue(sampleEntity.didCallAfterDelete0)
    }
}

