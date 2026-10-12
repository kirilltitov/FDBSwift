import FDB
import FDBEntity
import Foundation
import Testing

/// Database for the tests, see `TestEnvironment` in FDBTests (the same environment variables are honored)
let db: FDB.Database = {
    if let version = ProcessInfo.processInfo.environment["FDB_TEST_API_VERSION"].flatMap({ Int32($0) }),
       version != FDB.latestAPIVersion
    {
        try! FDB.Network.selectAPIVersion(version)
    }
    return try! FDB.Database()
}()

/// Root subspace of this test run
let testSubspace = FDB.Subspace("fdbentity-tests", UUID())

struct User: FDB.IndexedEntity, Equatable {
    enum IndexKey: String, FDB.EntityIndexKey {
        case email, country, like
    }

    static var storage: any FDB.Transactor { db }
    static var subspace: FDB.Subspace { testSubspace }
    static var IDKey: KeyPath<User, FDB.UUID> { \.ID }

    static let indices: [IndexKey: FDB.EntityIndex<User>] = [
        .email: FDB.EntityIndex(\.email, unique: true),
        .country: FDB.EntityIndex(\.country, unique: false),
    ]

    let ID: FDB.UUID
    var email: String
    var country: String
    var name = "Name"
}

struct Comment: FDB.Entity, Equatable {
    static var storage: any FDB.Transactor { db }
    static var subspace: FDB.Subspace { testSubspace }
    static let format: FDB.EntityFormat = .MsgPack
    static var IDKey: KeyPath<Comment, Int> { \.ID }

    let ID: Int
    var body: String
    var failOnSave = false

    func afterSave(within _: borrowing FDB.Transaction) async throws {
        struct Failure: Error {}
        if self.failOnSave {
            throw Failure()
        }
    }
}

/// The same layout as in production data written by Entita2FDB (expected bytes are made with Python's tuple layer)
struct GoldenUser: FDB.IndexedEntity {
    enum IndexKey: String, FDB.EntityIndexKey {
        case email, country
    }

    static var storage: any FDB.Transactor { db }
    static var subspace: FDB.Subspace { FDB.Subspace("app") }
    static var entityName: String { "User" }
    static var IDKey: KeyPath<GoldenUser, FDB.UUID> { \.ID }
    static let indices: [IndexKey: FDB.EntityIndex<GoldenUser>] = [
        .email: FDB.EntityIndex(\.email, unique: true),
        .country: FDB.EntityIndex(\.country, unique: false),
    ]

    let ID: FDB.UUID
    var email: String
    var country: String
}

struct GoldenComment: FDB.Entity {
    static var storage: any FDB.Transactor { db }
    static var subspace: FDB.Subspace { FDB.Subspace("app") }
    static var entityName: String { "Comment" }
    static var IDKey: KeyPath<GoldenComment, Int> { \.ID }

    let ID: Int
}

func randomEmail() -> String {
    "\(UUID().uuidString)@example.com"
}

@Suite("FDBEntity")
struct FDBEntityTests {
    @Test func keyLayout() {
        let id = FDB.UUID("347B4A97-C267-423F-A847-880246FC6972")!
        let user = GoldenUser(ID: id, email: "a@b.c", country: "RU")
        let uuidBytes: Bytes = [
            0x34, 0x7B, 0x4A, 0x97, 0xC2, 0x67, 0x42, 0x3F, 0xA8, 0x47, 0x88, 0x02, 0x46, 0xFC, 0x69, 0x72,
        ]
        let app: Bytes = [0x02, 0x61, 0x70, 0x70, 0x00]
        let userName: Bytes = [0x02, 0x55, 0x73, 0x65, 0x72, 0x00]
        let idx: Bytes = [0x02, 0x69, 0x64, 0x78, 0x00]
        let packedID: Bytes = [0x01] + uuidBytes + [0x00]
        let email: Bytes = [0x02, 0x65, 0x6D, 0x61, 0x69, 0x6C, 0x00, 0x02, 0x61, 0x40, 0x62, 0x2E, 0x63, 0x00]
        let country: Bytes = [0x02, 0x63, 0x6F, 0x75, 0x6E, 0x74, 0x72, 0x79, 0x00, 0x02, 0x52, 0x55, 0x00]

        #expect(id.bytes == uuidBytes)
        #expect(user.getIDAsKey() == app + userName + packedID)
        #expect(GoldenComment.IDAsKey(ID: 42) == app + [0x02, 0x43, 0x6F, 0x6D, 0x6D, 0x65, 0x6E, 0x74, 0x00, 0x15, 0x2A])
        #expect(GoldenUser.getIndexKeyForUniqueIndex(key: .email, value: "a@b.c").prefix == app + idx + userName + email)
        #expect(
            user.getIndexKeyForIndex(GoldenUser.indices[.country]!, key: .country, value: "RU").prefix
                == app + idx + userName + country + packedID
        )
        #expect(user.getIndexIndexKeyForIndex(key: .email, value: "a@b.c").prefix == app + idx + userName + idx + packedID + email)
    }

    /// The serialized form of UUID IDs must not change: it's in the stored data
    @Test func uuidCoding() throws {
        let json = #"{"ID":"NHtKl8JnQj+oR4gCRvxpcg==","email":"a@b.c","country":"RU"}"#
        let user = try GoldenUser(from: Bytes(json.utf8))
        #expect(user.ID.string == "347B4A97-C267-423F-A847-880246FC6972")
        #expect(String(decoding: try user.pack(), as: UTF8.self).contains(#""ID":"NHtKl8JnQj+oR4gCRvxpcg==""#))
        #expect(FDB.UUID(bytes: [1, 2, 3]) == nil)
        #expect(try FDB.Tuple(user.ID).unpack(as: FDB.UUID.self) == user.ID)
    }

    @Test func crud() async throws {
        let comment = Comment(ID: Int.random(in: 1 ... .max), body: "Hello")
        #expect(try await Comment.load(by: comment.ID) == nil)

        try await comment.insert()
        #expect(try await Comment.load(by: comment.ID) == comment)
        #expect(try await Comment.exists(by: comment.ID))
        await #expect(throws: FDB.EntityError.self) {
            try await comment.insert()
        }

        var edited = comment
        edited.body = "Edited"
        try await edited.save()
        #expect(try await Comment.load(by: comment.ID) == edited)

        try await edited.delete()
        #expect(try await Comment.load(by: comment.ID) == nil)
    }

    @Test func atomicity() async throws {
        let first = Comment(ID: Int.random(in: 1 ... .max), body: "first")
        let second = Comment(ID: Int.random(in: 1 ... .max), body: "second", failOnSave: true)

        await #expect(throws: (any Error).self) {
            try await db.withTransaction { tr in
                try await first.save(within: tr)
                try await second.save(within: tr)
            }
        }
        #expect(try await Comment.load(by: first.ID) == nil)
        #expect(try await Comment.load(by: second.ID) == nil)
    }

    @Test func loadAll() async throws {
        let ids = [FDB.UUID(), FDB.UUID(), FDB.UUID()]
        let country = UUID().uuidString
        for id in ids {
            try await User(ID: id, email: randomEmail(), country: country).insert()
        }
        let all = try await User.loadAll()
        #expect(Set(ids).isSubset(of: Set(all.map(\.ID))))
        #expect(try await User.loadAll(limit: 2).count == 2)
    }

    @Test func indices() async throws {
        let country = UUID().uuidString
        var user = User(ID: FDB.UUID(), email: randomEmail(), country: country)
        try await user.insert()

        #expect(try await User.loadByIndex(key: .email, value: user.email) == user)
        #expect(try await User.existsByIndex(key: .email, value: user.email))
        #expect(try await User.loadAllByIndex(key: .country, value: country) == [user])

        // Changing indexed values moves the index entries
        let oldEmail = user.email
        user.email = randomEmail()
        user.country = UUID().uuidString
        try await user.save()
        #expect(try await User.loadByIndex(key: .email, value: oldEmail) == nil)
        #expect(try await User.loadByIndex(key: .email, value: user.email) == user)
        #expect(try await User.loadAllByIndex(key: .country, value: country).isEmpty)
        #expect(try await User.loadAllByIndex(key: .country, value: user.country) == [user])

        // Saving without changes keeps them
        user.name = "Other name"
        try await user.save()
        #expect(try await User.loadByIndex(key: .email, value: user.email) == user)

        try await user.delete()
        #expect(try await User.loadByIndex(key: .email, value: user.email) == nil)
        #expect(try await User.loadAllByIndex(key: .country, value: user.country).isEmpty)
        let leftovers = try await db.getAll(user.indexIndexSubspace.range)
        #expect(leftovers.isEmpty)

        await #expect(throws: FDB.EntityError.self) {
            try await user.delete()
        }
    }

    @Test func uniqueIndexIsEnforced() async throws {
        let email = randomEmail()
        let first = User(ID: FDB.UUID(), email: email, country: "RU")
        try await first.insert()

        let second = User(ID: FDB.UUID(), email: email, country: "RU")
        await #expect(throws: FDB.EntityError.self) {
            try await second.insert()
        }
        var third = User(ID: FDB.UUID(), email: randomEmail(), country: "RU")
        try await third.insert()
        third.email = email
        await #expect(throws: FDB.EntityError.self) {
            try await third.save()
        }

        // Nothing is broken for the owner
        #expect(try await User.loadByIndex(key: .email, value: email) == first)
        #expect(try await User.load(by: second.ID) == nil)
    }

    @Test func concurrentUniqueValues() async throws {
        let email = randomEmail()
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 5 {
                group.addTask {
                    (try? await User(ID: FDB.UUID(), email: email, country: "RU").insert()) != nil
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.filter { $0 }.count == 1)
    }

    @Test func indexMisuse() async throws {
        await #expect(throws: FDB.EntityError.self) {
            try await User.loadByIndex(key: .country, value: "RU")
        }
        await #expect(throws: FDB.EntityError.self) {
            try await User.loadByIndex(key: .like, value: "x")
        }
    }

    @Test func customIndexIndexEntriesSurviveSaves() async throws {
        var user = User(ID: FDB.UUID(), email: randomEmail(), country: "RU")
        try await user.insert()
        // E.g. likes of a user, stored next to the indexed values
        let likeKey = user.getIndexIndexKeyForIndex(key: .like, value: 42)
        try await db.set(key: likeKey, value: [])

        user.email = randomEmail()
        try await user.save()
        #expect(try await db.get(key: likeKey) == [])
    }
}
