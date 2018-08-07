import XCTest
import NIO
@testable import FDB

class FDBTests: XCTestCase {
    static var fdb: FDB!
    static var subspace: Subspace!
    
    let eventLoop = EmbeddedEventLoop()
    
    var semaphore: DispatchSemaphore {
        return DispatchSemaphore(value: 0)
    }

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
        self.fdb.disconnect()
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
    
    func begin() throws -> Transaction {
        return try FDBTests.fdb.begin(eventLoop: self.eventLoop)
    }
    
    func genericTestCommit() throws -> Transaction {
        let tr = try self.begin()
        var ran = false
        let semaphore = self.semaphore
        tr.commit().whenSuccess {
            ran = true
            semaphore.signal()
        }
        semaphore.wait()
        XCTAssertTrue(ran)
        return tr
    }
    
    func testNIOCommit() throws {
        let _ = try self.genericTestCommit()
    }

    func testNIOFailingCommit() throws {
        let tr = try self.genericTestCommit()
        let semaphore = self.semaphore
        var counter: Int = 0
        tr.commit().whenFailure { error in
            counter += 1
            guard case FDB.Error.UsedDuringCommit = error else {
                XCTFail("Error must be UsedDuringCommit")
                semaphore.signal()
                return
            }
            semaphore.signal()
        }
        XCTAssertEqual(counter, 0)
        semaphore.wait()
        XCTAssertEqual(counter, 1)
    }

    func testNIOSetGet() throws {
        let tr = try self.begin()
        let semaphore = self.semaphore
        let key = FDBTests.subspace["set"]
        let value = self.getRandomBytes()
        let _: EventLoopFuture<Void> = tr
            .set(key: key, value: value)
            .then { tr.get(key: key) }
            .map { bytes in
                XCTAssertEqual(bytes, value)
                semaphore.signal()
                return
            }
        semaphore.wait()
    }

    func testNIOGetRange() throws {
        let tr = try self.begin()
        let semaphore = self.semaphore
        let limit = 2
        let subspace = FDBTests.subspace["range"]
        var values: [KeyValue] = []
        for i in 0..<limit {
            let key = subspace["sub \(i)"].asFDBKey()
            let value = self.getRandomBytes()
            values.append(KeyValue(key: key, value: value))
            let _ = try tr.set(key: key, value: value).wait()
        }
        let _: Void = try tr.commit().wait()
        let tr2 = try self.begin()
        let expected = KeyValuesResult(result: values, hasMore: false)
        XCTAssertEqual(try tr2.get(range: subspace.range).wait(), expected)
        let _ = tr2
            .get(begin: subspace.range.begin, end: subspace.range.end)
            .map { (values) -> Void in
                XCTAssertEqual(values, expected)
                semaphore.signal()
                return
            }
        semaphore.wait()
    }

    func testNIOAtomicAdd() throws {
        let tr = try self.begin()
        let semaphore = self.semaphore
        let key = FDBTests.subspace.subspace("atomic_incr")
        let step: Int64 = 1
        let expected = step + 1
        for _ in 0..<expected - 1 {
            let _ = try tr.atomic(.Add, key: key, value: step).wait()
        }
//      TODO
//      XCTAssertNoThrow(try tr.increment(key: key))
        tr.atomic(.Add, key: key, value: step).whenComplete {
            semaphore.signal()
        }
        semaphore.wait()
        let result = try tr.get(key: key).wait()
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.cast() as Int64, expected)
        XCTAssertEqual(result, getBytes(expected))
//      TODO
//      XCTAssertEqual(try fdb.increment(key: key), expected + 1)
//      XCTAssertEqual(try fdb.increment(key: key, value: -1), expected)
//      XCTAssertEqual(try fdb.decrement(key: key), expected - 1)
//      XCTAssertEqual(try fdb.decrement(key: key), 0)
    }

    func testNIOClear() throws {
        let tr = try self.begin()
        let semaphore = self.semaphore
        let future = tr.clear(key: FDBTests.subspace["empty"]).then(tr.commit)
        future.whenFailure { error in
            XCTFail("Error: \(error)")
        }
        future.whenComplete {
            semaphore.signal()
        }
        semaphore.wait()
    }

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
        ("testNIOCommit", testNIOCommit),
        ("testNIOFailingCommit", testNIOFailingCommit),
        ("testNIOSetGet", testNIOSetGet),
        ("testNIOGetRange", testNIOGetRange),
        ("testNIOAtomicAdd", testNIOAtomicAdd),
        ("testNIOClear", testNIOClear),
    ]
}
