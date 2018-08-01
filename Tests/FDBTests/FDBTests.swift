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
        dump("TEAR DOWN 1")
        super.tearDown()
        do {
            dump("TEAR DOWN 2")
            try self.fdb.clear(subspace: self.subspace)
            dump("TEAR DOWN 3")
        } catch {
            XCTFail("Could not tearDown: \(error)")
        }
        dump("TEAR DOWN 4")
        self.fdb = nil
    }

    func getRandomBytes() -> Bytes {
        var bytes = Bytes()
        for _ in 0..<UInt.random(in: 1..<50) {
            bytes.append(UInt8.random(in: 0..<UInt8.max))
        }
        return bytes
    }

    func testConnect() throws {
        XCTAssertNoThrow(try FDBTests.fdb.connect())
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
        transaction.set(key: key, value: value)
        XCTAssertEqual(try transaction.get(key: key), value)
        XCTAssertNoThrow(try transaction.commit().waitAndCheck())
        // transaction is already closed
        XCTAssertThrowsError(try transaction.commit().waitAndCheck())
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
        let expected = KeyValuesResult(result: values, hasMore: false)
        XCTAssertEqual(try FDBTests.fdb.get(subspace: subspace), expected)
        XCTAssertEqual(try FDBTests.fdb.get(range: subspace.range), expected)
        XCTAssertEqual(try FDBTests.fdb.get(begin: subspace.range.begin, end: subspace.range.end), expected)
    }

    func testAtomicAdd() throws {
        let fdb = FDBTests.fdb!
        let key = FDBTests.subspace.subspace("atomic_incr")
        let step: Int64 = 1
        let expected = step + 1
        for _ in 0..<expected - 1 {
            XCTAssertNoThrow(try fdb.atomic(.Add, key: key, value: step))
        }
        XCTAssertNoThrow(try fdb.increment(key: key))
        let result = try fdb.get(key: key)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.cast() as Int64, expected)
        XCTAssertEqual(result, getBytes(expected))
        XCTAssertEqual(try fdb.increment(key: key), expected + 1)
        XCTAssertEqual(try fdb.increment(key: key, value: -1), expected)
        XCTAssertEqual(try fdb.decrement(key: key), expected - 1)
        XCTAssertEqual(try fdb.decrement(key: key), 0)
    }

    func testClear() throws {
        XCTAssertNoThrow(try FDBTests.fdb.clear(key: FDBTests.subspace["empty"]))
    }

    func testStringKeys() throws {
        let fdb = FDBTests.fdb!
        let key = "foo"
        let value: Bytes = [0,1,2]
        XCTAssertNoThrow(try fdb.set(key: key, value: value))
        XCTAssertEqual(try fdb.get(key: key), value)
    }

    func testStaticStringKeys() throws {
        let fdb = FDBTests.fdb!
        let key: StaticString = "foo"
        let value: Bytes = [0,1,2]
        XCTAssertNoThrow(try fdb.set(key: key, value: value))
        XCTAssertEqual(try fdb.get(key: key), value)
    }

    func testErrorDescription() {
        let error = FDB.Error.self
        XCTAssertEqual(error.TransactionReadOnly.rawValue, 2021)
        XCTAssertEqual(error.TransactionReadOnly.getDescription(), "Transaction is read-only and therefore does not have a commit version")
        XCTAssertEqual(error.TransactionRetry.getDescription(), "You should replay this transaction")
        XCTAssertEqual(error.UnexpectedError.getDescription(), "Error is unexpected, it shouldn't really happen")
    }
    
//    func testFutureCallback() {
//        let semaphore = DispatchSemaphore(value: 0)
//        
//    }

    static var allTests = [
        ("testEmptyValue", testEmptyValue),
        ("testSetGetBytes", testSetGetBytes),
        ("testTransaction", testTransaction),
        ("testGetRange", testGetRange),
        ("testAtomicAdd", testAtomicAdd),
        ("testClear", testClear),
        ("testStringKeys", testStringKeys),
        ("testStaticStringKeys", testStaticStringKeys),
        ("testErrorDescription", testErrorDescription),
    ]
}
