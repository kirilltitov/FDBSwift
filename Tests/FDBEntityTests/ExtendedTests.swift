import Foundation
import XCTest
import FDB
import MessagePack
import LGNLog
@testable import FDBEntity

final class ExtendedTests: XCTestCase {
    static var fdb: FDB.Connector = FDB.Connector()
    static var subspace: FDB.Subspace!

    struct TestEntity: FDBIndexedEntity, Equatable {
        typealias Identifier = FDB.UUID

        public enum IndexKey: String, AnyIndexKey {
            case email, country, invalidIndex
        }

        static var storage: any FDBConnector = fdb
        static var subspace: FDB.Subspace = ExtendedTests.subspace
        static var format: FDB.Entity.Format = .JSON
        static var IDKey: KeyPath<Self, Identifier> = \.ID

        static var indices: [IndexKey: FDB.Index<Self>] = [
            .email: FDB.Index(\.email, unique: true),
            .country: FDB.Index(\.country, unique: false),
        ]

        let ID: Identifier
        var email: String
        var country: String
    }

    let email1 = "foo"
    let email2 = "bar"
    let email3 = "baz"
    let email4 = "sas"

    override class func setUp() {
        super.setUp()
        LGNLogger.logLevel = .trace
        try! self.fdb.connect()
        self.subspace = FDB.Subspace("test \(Int.random(in: 0 ..< Int.max))")
    }

    override class func tearDown() {
        super.tearDown()
        Logger.current.notice("Cleanup")
        // do {
        //     try self.fdb.clear(subspace: self.subspace)
        // } catch {
        //     XCTFail("Could not tearDown: \(error)")
        // }
        self.fdb.disconnect()
    }

    private func cleanup() async throws {
        try await Self.fdb.clear(subspace: Self.subspace)
    }

    override func setUp() async throws {
        try await self.cleanup()
    }

    override func tearDown() async throws {
        try await self.cleanup()
    }

    func testGeneric() async throws {
        let id1 = FDB.UUID()
        var instance1 = TestEntity(
            ID: id1,
            email: "jennie.pink@mephone.org.uk",
            country: "UK"
        )

        let transaction: any FDBTransaction = try Self.fdb.begin()
        try await instance1.insert(within: transaction, commit: true)
        let actual1 = try await TestEntity.load(by: id1)
        XCTAssertEqual(instance1, actual1)
        let actual2 = try await TestEntity.loadByIndex(key: .email, value: "jennie.pink@mephone.org.uk")
        XCTAssertEqual(instance1, actual2)

        instance1.email = "bender@ilovebender.com"
        try await instance1.save()
        let actual3 = try await TestEntity.loadByIndex(key: .email, value: "bender@ilovebender.com")
        XCTAssertEqual(instance1, actual3)

        try await instance1.delete()
    }

    func test_loadAllByIndex_loadAll() async throws {
        let uuid1 = FDB.UUID("AAAAAAAA-F0AB-4782-9267-B52CF61B7E1A")!
        let uuid2 = FDB.UUID("BBBBBBBB-F0AB-4782-9267-B52CF61B7E1A")!
        let uuid3 = FDB.UUID("CCCCCCCC-F0AB-4782-9267-B52CF61B7E1A")!
        let uuid4 = FDB.UUID("DDDDDDDD-F0AB-4782-9267-B52CF61B7E1A")!
        let instance1 = TestEntity(ID: uuid1, email: self.email1, country: "RU")
        let instance2 = TestEntity(ID: uuid2, email: self.email2, country: "RU")
        let instance3 = TestEntity(ID: uuid3, email: self.email3, country: "UA")
        let instance4 = TestEntity(ID: uuid4, email: self.email4, country: "KE")

        try await instance1.insert()
        try await instance2.insert()
        try await instance3.insert()
        try await instance4.insert()

        func load1() async throws -> [(ID: TestEntity.Identifier, value: TestEntity)] {
            try await TestEntity.loadAll(bySubspace: Self.subspace[TestEntity.entityName], snapshot: true)
        }

        let result1 = try await load1()
        XCTAssertEqual(
            [instance1, instance2, instance3, instance4],
            result1.map { $0.value }
        )
        XCTAssertEqual(
            [instance1.ID, instance2.ID, instance3.ID, instance4.ID],
            result1.map { $0.ID }
        )

        func load2() async throws -> [(ID: TestEntity.Identifier, value: TestEntity)] {
            try await TestEntity.loadAll(snapshot: true)
        }

        let result2 = try await load2()
        XCTAssertEqual(
            [instance1, instance2, instance3, instance4],
            result2.map { $0.value }
        )
        XCTAssertEqual(
            [instance1.ID, instance2.ID, instance3.ID, instance4.ID],
            result2.map { $0.ID }
        )

        let result3 = try await TestEntity.loadAllByIndex(key: .country, value: "RU")
        XCTAssertEqual(
            [instance1, instance2],
            result3
        )

        var instance4_1 = try await TestEntity.loadByIndex(
            key: .email,
            value: self.email4
        )
        XCTAssertNotNil(instance4_1)
        instance4_1!.email = "kek"
        try await instance4_1!.save()

        /// Ensure that subspace is empty after deletion
        let actualDeleted1 = try await Self.fdb.get(range: Self.subspace.range).records.count
        XCTAssertNotEqual(0, actualDeleted1)

        try await instance1.delete()
        try await instance2.delete()
        try await instance3.delete()
        try await instance4.delete()

        let actualDeleted2 = try await Self.fdb.get(range: Self.subspace.range).records
        XCTAssertEqual(0, actualDeleted2.count)
    }

    func testLoadWithTransaction() async throws {
        enum E: Error {
            case err
        }
        let instance1 = TestEntity(ID: .init(), email: "foo", country: "UA")
        try await instance1.save()

        let transaction: any FDBTransaction = try Self.fdb.begin()

        let maybeEntity = try await TestEntity.load(by: instance1.ID, within: transaction, snapshot: false)
        guard let entity = maybeEntity else {
            throw E.err
        }
        try await entity.delete(within: transaction, commit: false)

        transaction.reset()

        let actual = try await TestEntity.load(by: instance1.ID, within: transaction, snapshot: false)

        XCTAssertEqual(instance1, actual)
    }

    func testExistsByIndex() async throws {
        let email = "foo@bar.baz"
        let actual1 = try await TestEntity.existsByIndex(key: .email, value: email)
        XCTAssertFalse(actual1)
        try await TestEntity(ID: .init(), email: email, country: "RU").save()
        let actual2 = try await TestEntity.existsByIndex(key: .email, value: email)
        XCTAssertTrue(actual2)
        let instance = try await TestEntity.loadByIndex(
            key: .email,
            value: email
        )
        XCTAssertNotNil(instance)
        try await instance!.delete()
        let actual3 = try await TestEntity.existsByIndex(key: .email, value: email)
        XCTAssertFalse(actual3)
    }

    func testInvalidIndex() async throws {
        let actual1 = try await TestEntity.existsByIndex(key: .invalidIndex, value: "lul")
        XCTAssertEqual(false, actual1)
        let actual2 = try await TestEntity.loadAllByIndex(key: .invalidIndex, value: "lul")
        XCTAssertEqual([], actual2)
        let actual3 = try await TestEntity.loadByIndex(key: .invalidIndex, value: "lul")
        XCTAssertEqual(nil, actual3)
        let actual4 = try await TestEntity.loadByIndex(key: .email, value: "lul")
        XCTAssertEqual(nil, actual4)
    }

    func testDoesRelateToThis() throws {
        let instance = TestEntity(ID: .init(), email: "foo", country: "UA")
        let key = instance.getIDAsKey()
        let tuple = try FDB.Tuple(from: key)
        XCTAssertTrue(TestEntity.doesRelateToThis(tuple: tuple))
        XCTAssertFalse(TestEntity.doesRelateToThis(tuple: FDB.Tuple("foo", "bar")))
        XCTAssertFalse(TestEntity.doesRelateToThis(tuple: FDB.Tuple("foo")))
        XCTAssertFalse(TestEntity.doesRelateToThis(tuple: FDB.Tuple()))
    }
}
