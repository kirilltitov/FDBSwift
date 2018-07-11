import XCTest
@testable import FDB

class FDBTests: XCTestCase {
    static var fdb: FDB!
    static var subspace: Subspace!

    override class func setUp() {
        super.setUp()
        self.fdb = FDB()
        self.subspace = Subspace("test \(Int.random(in: 0..<Int.max))")
    }

    override class func tearDown() {
        super.tearDown()
        do {
            try self.fdb.clear(subspace: self.subspace)
        } catch {
            XCTFail("Could not tearDown: \(error)")
        }
        self.fdb = nil
    }

    func getRandomBytes() -> Bytes {
        var bytes = Bytes()
        for _ in 0..<UInt.random(in: 1..<50) {
            bytes.append(UInt8.random(in: 0..<UInt8.max))
        }
        return bytes
    }

    func testEmptyValue() throws {
        XCTAssertNil(try FDBTests.fdb.get(key: FDBTests.subspace[nil]), "Non-nil value returned")
    }

    func testSetGetBytes() throws {
        let key = FDBTests.subspace["set"]
        let value = self.getRandomBytes()
        try FDBTests.fdb.set(key: key, value: value)
        XCTAssertEqual(try FDBTests.fdb.get(key: key), value)
    }

    func testTransaction() throws {
        let key = FDBTests.subspace["transaction"]
        let value = self.getRandomBytes()
        let transaction = try FDBTests.fdb.begin()
        try transaction.set(key: key, value: value)
        XCTAssertEqual(try transaction.get(key: key), value)
        try transaction.commit()
        // transaction is already closed
        XCTAssertThrowsError(try transaction.commit())
    }

    func testGetRange() throws {
        let limit = 2
        let subspace = FDBTests.subspace["range"]
        var values: [KeyValue] = []
        for i in 0..<limit {
            let key = subspace["sub \(i)"].asFDBKey()
            let value = self.getRandomBytes()
            values.append(KeyValue(key: key, value: value))
            try FDBTests.fdb.set(key: key, value: value)
        }
        XCTAssertEqual(try FDBTests.fdb.get(subspace: subspace), values)
        XCTAssertEqual(try FDBTests.fdb.get(range: subspace.range), values)
        XCTAssertEqual(try FDBTests.fdb.get(begin: subspace.range.begin, end: subspace.range.end), values)
    }

    static var allTests = [
        ("testEmptyValue", testEmptyValue),
        ("testSetGetBytes", testSetGetBytes),
        ("testTransaction", testTransaction),
        ("testGetRange", testGetRange),
    ]
}
