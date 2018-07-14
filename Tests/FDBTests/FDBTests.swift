import XCTest
@testable import FDB

fileprivate extension Array where Element == Byte {
    func cast<Result>() -> Result {
        precondition(
            MemoryLayout<Result>.size == self.count,
            "Memory layout size for result type '\(Result.self)' (\(MemoryLayout<Result>.size) bytes) does not match with given byte array length (\(self.count) bytes)"
        )
        return self.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: Result.self).pointee
        }
    }
}

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

    func testAtomicAdd() throws {
        let key = FDBTests.subspace["atomic_incr"]
        let step: Int64 = 1
        let expected = step + 1
        for _ in 0..<expected - 1 {
            try FDBTests.fdb.atomic(.Add, key: key, value: step)
        }
        try FDBTests.fdb.increment(key: key)
        let result = try FDBTests.fdb.get(key: key)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.cast() as Int64, expected)
        XCTAssertEqual(result, getBytes(expected))
    }

    static var allTests = [
        ("testEmptyValue", testEmptyValue),
        ("testSetGetBytes", testSetGetBytes),
        ("testTransaction", testTransaction),
        ("testGetRange", testGetRange),
        ("testAtomicAdd", testAtomicAdd),
    ]
}
