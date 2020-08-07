@testable import FDB
import NIO
import XCTest
import Logging

class FDBTests: XCTestCase {
    static var fdb: FDB!
    static var subspace: FDB.Subspace!

    let eventLoop = EmbeddedEventLoop()

    var semaphore: DispatchSemaphore {
        return DispatchSemaphore(value: 0)
    }

    override class func setUp() {
        super.setUp()
        var logger = Logger(label: "testlogger")
        logger.logLevel = .debug
        FDB.logger = logger
        self.fdb = FDB()
        self.subspace = FDB.Subspace("test \(Int.random(in: 0 ..< Int.max))")
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
        for _ in 0 ..< UInt.random(in: 1 ..< 50) {
            bytes.append(UInt8.random(in: 0 ..< UInt8.max))
        }
        return bytes
    }

    func testConnect() throws {
        XCTAssertNoThrow(try FDBTests.fdb.connect())
    }

    func testEmptyValue() throws {
        XCTAssertNil(try FDBTests.fdb.get(key: FDBTests.subspace[FDB.Null()]), "Non-nil value returned")
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
        let transaction = try FDBTests.fdb.begin() as! FDB.Transaction
        transaction.set(key: key, value: value)
        XCTAssertEqual(try transaction.get(key: key), value)
        XCTAssertNoThrow(try transaction.commit().waitAndCheck())
        // transaction is already closed
        XCTAssertThrowsError(try transaction.commit().waitAndCheck())
    }

    func testGetRange() throws {
        let limit = 2
        let subspace = FDBTests.subspace["range"]
        var values: [FDB.KeyValue] = []
        for i in 0 ..< limit {
            let key = subspace["sub \(i)"].asFDBKey()
            let value = self.getRandomBytes()
            values.append(FDB.KeyValue(key: key, value: value))
            try FDBTests.fdb.set(key: key, value: value)
        }
        let expected = FDB.KeyValuesResult(records: values, hasMore: false)
        XCTAssertEqual(try FDBTests.fdb.get(subspace: subspace), expected)
        XCTAssertEqual(try FDBTests.fdb.get(range: subspace.range), expected)
        XCTAssertEqual(try FDBTests.fdb.get(begin: subspace.range.begin, end: subspace.range.end), expected)
    }

    func testAtomicAdd() throws {
        let fdb = FDBTests.fdb!
        let key = FDBTests.subspace.subspace("atomic_incr")
        let step: Int64 = 1
        let expected = step + 1
        for _ in 0 ..< expected - 1 {
            XCTAssertNoThrow(try fdb.atomic(.add, key: key, value: step))
        }
        XCTAssertNoThrow(try fdb.increment(key: key))
        let result = try fdb.get(key: key)
        XCTAssertNotNil(result)
        try XCTAssertEqual(result!.cast() as Int64, expected)
        XCTAssertEqual(result, getBytes(expected))
        XCTAssertEqual(try fdb.increment(key: key), expected + 1)
        XCTAssertEqual(try fdb.increment(key: key, value: -1), expected)
        XCTAssertEqual(try fdb.decrement(key: key), expected - 1)
        XCTAssertEqual(try fdb.decrement(key: key), 0)
    }

    func testSetVersionstampedKey() throws {
        let fdb = FDBTests.fdb!
        let subspace = FDBTests.subspace.subspace("atomic_versionstamp")
        let key = subspace[FDB.Versionstamp(userData: 42)]["mykey"]
        
        let value: String = "hello!"
        
        let tr = try self.begin().wait()
        XCTAssertNoThrow(try tr.set(versionstampedKey: key, value: getBytes(value.utf8)) as Void)
        XCTAssertNoThrow(try tr.commitSync())
    }

    func testClear() throws {
        XCTAssertNoThrow(try FDBTests.fdb.clear(key: FDBTests.subspace["empty"]))
    }

    func testStringKeys() throws {
        let fdb = FDBTests.fdb!
        let key = "foo"
        let value: Bytes = [0, 1, 2]
        XCTAssertNoThrow(try fdb.set(key: key, value: value))
        XCTAssertEqual(try fdb.get(key: key), value)
    }

    func testStaticStringKeys() throws {
        let fdb = FDBTests.fdb!
        let key: StaticString = "foo"
        let value: Bytes = [0, 1, 2]
        XCTAssertNoThrow(try fdb.set(key: key, value: value))
        XCTAssertEqual(try fdb.get(key: key), value)
    }

    func testErrorDescription() {
        typealias E = FDB.Error
        XCTAssertEqual(E.transactionReadOnly.errno, 2021)
        XCTAssertEqual(E.transactionReadOnly.getDescription(), "Transaction is read-only and therefore does not have a commit version")
        XCTAssertEqual(E.unexpectedError("FOo bar").getDescription(), "Error is unexpected, it shouldn't really happen")
    }

    func begin() throws -> EventLoopFuture<AnyFDBTransaction> {
        return FDBTests.fdb.begin(on: self.eventLoop)
    }

    func genericTestCommit() throws -> AnyFDBTransaction {
        FDB.logger.info("Starting transaction")
        let tr = try self.begin().wait()
        let _ = try tr.set(key: FDBTests.subspace["testcommit"], value: Bytes([1,2,3])).wait()
        FDB.logger.info("Started transaction")
        var ran = false
        let semaphore = self.semaphore
        tr.commit().whenSuccess {
            FDB.logger.info("Transaction committed")
            ran = true
            semaphore.signal()
        }
        FDB.logger.info("Waiting for semaphore")
        let _ = semaphore.wait(for: 10)
        FDB.logger.info("Semaphore done")
        XCTAssertTrue(ran)
        return tr
    }

    func testNIOCommit() throws {
        _ = try self.genericTestCommit()
    }

    func testNIOFailingCommit() throws {
        let tr = try self.genericTestCommit()
        let semaphore = self.semaphore
        var counter: Int = 0
        tr.commit().whenFailure { error in
            counter += 1
            guard case FDB.Error.usedDuringCommit = error else {
                XCTFail("Error must be UsedDuringCommit")
                semaphore.signal()
                return
            }
            semaphore.signal()
        }
        XCTAssertEqual(counter, 0)
        let _ = semaphore.wait(for: 10)
        XCTAssertEqual(counter, 1)
    }

    func testNIOSetGet() throws {
        let semaphore = self.semaphore
        let tr = try self.begin().wait()
        let key = FDBTests.subspace["set"]
        let value = self.getRandomBytes()
        let _: EventLoopFuture<Void> = tr
            .set(key: key, value: value)
            .flatMap { $0.get(key: key) }
            .map { (bytes, _) in
                XCTAssertEqual(bytes, value)
                semaphore.signal()
                return
            }
        let _ = semaphore.wait(for: 10)
    }

    func testNIOGetRange() throws {
        let semaphore = self.semaphore
        let tr = try self.begin().wait()
        let limit = 2
        let subspace = FDBTests.subspace["range"]
        var values: [FDB.KeyValue] = []
        for i in 0 ..< limit {
            let key = subspace["sub \(i)"].asFDBKey()
            let value = self.getRandomBytes()
            values.append(FDB.KeyValue(key: key, value: value))
            _ = try tr.set(key: key, value: value).wait()
        }
        let _: Void = try tr.commit().wait()
        let tr2 = try self.begin().wait()
        let expected = FDB.KeyValuesResult(records: values, hasMore: false)
        XCTAssertEqual(try tr2.get(range: subspace.range).wait(), expected)
        _ = tr2
            .get(begin: subspace.range.begin, end: subspace.range.end)
            .map { (values, _) -> Void in
                XCTAssertEqual(values, expected)
                semaphore.signal()
                return
            }
        let _ = semaphore.wait(for: 10)
    }

    func testNIOAtomicAdd() throws {
        let tr = try self.begin().wait()
        let semaphore = self.semaphore
        let key = FDBTests.subspace.subspace("atomic_incr")
        let step: Int64 = 1
        let expected = step + 1
        for _ in 0 ..< expected - 1 {
            _ = try tr.atomic(.add, key: key, value: step).wait()
        }
//      TODO:
//      XCTAssertNoThrow(try tr.increment(key: key))
        tr.atomic(.add, key: key, value: step).whenComplete { _ in
            semaphore.signal()
        }
        let _ = semaphore.wait(for: 10)
        let result: Bytes? = try tr.get(key: key).wait()
        XCTAssertNotNil(result)
        try XCTAssertEqual(result!.cast() as Int64, expected)
        XCTAssertEqual(result, getBytes(expected))
//      TODO:
//      XCTAssertEqual(try fdb.increment(key: key), expected + 1)
//      XCTAssertEqual(try fdb.increment(key: key, value: -1), expected)
//      XCTAssertEqual(try fdb.decrement(key: key), expected - 1)
//      XCTAssertEqual(try fdb.decrement(key: key), 0)
    }

    func testNIOClear() throws {
        let tr = try self.begin().wait()
        let semaphore = self.semaphore
        let future = tr
            .clear(key: FDBTests.subspace["empty"])
            .flatMap { $0.commit() }
        future.whenFailure { error in
            XCTFail("Error: \(error)")
        }
        future.whenComplete { _ in
            semaphore.signal()
        }
        let _ = semaphore.wait(for: 10)
    }

    func testTransactionOptions() throws {
        let tr = try self.begin().wait()
        let key = FDBTests.subspace["troptions"]
        XCTAssertNoThrow(try tr.setOption(.debugRetryLogging(transactionName: "testtransactionname")).wait())
        XCTAssertNoThrow(try tr.setOption(.transactionLoggingEnable(identifier: "identifier")).wait())
        XCTAssertNoThrow(try tr.setOption(.timeout(milliseconds: 1000)).wait())
        XCTAssertNoThrow(try tr.setOption(.retryLimit(retries: 4)).wait())
        XCTAssertNoThrow(try tr.setOption(.maxRetryDelay(milliseconds: 5000)).wait())
        XCTAssertNoThrow(try tr.set(key: key, value: Bytes([1,2,3])).wait())
        XCTAssertEqual(Bytes([1,2,3]), try tr.get(key: key).wait())
        let _: Void = try tr.commit().wait()
    }
    
    func testNetworkOptions() throws {
        XCTAssertThrowsError(try FDBTests.fdb.setOption(.TLSCertPath(path: "/tmp/invalidname")))
        XCTAssertThrowsError(try FDBTests.fdb.setOption(.TLSCABytes(bytes: Bytes([1,2,3]))))
        XCTAssertNoThrow(try FDBTests.fdb.setOption(.buggifyDisable))
        XCTAssertNoThrow(try FDBTests.fdb.setOption(.buggifySectionActivatedProbability(probability: 0)))
    }

    func testWrappedTransactions() throws {
        let etalon: [Int64] = (1...100).map { $0 }
        var resultSync = Array<Int64>()
        resultSync.reserveCapacity(etalon.count)
        var resultAsync = Array<Int64>()
        resultAsync.reserveCapacity(etalon.count)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        defer { try! group.syncShutdownGracefully() }

        let semaphoreSync = DispatchSemaphore(value: 0)
        let semaphoreAsync = DispatchSemaphore(value: 0)

        let keySync = FDBTests.subspace["increment_sync"]
        let keyAsync = FDBTests.subspace["increment_async"]

        try FDBTests.fdb.clear(key: keySync)
        try FDBTests.fdb.clear(key: keyAsync)

        let queue = DispatchQueue(label: "wrapped_test_queue", qos: .userInitiated, attributes: .concurrent)

        for _ in etalon {
            queue.async {
                let resultValue: Bytes? = try! FDBTests.fdb.withTransaction { transaction in
                    let _: Void = try transaction.atomic(.add, key: keySync, value: Int64(1))
                    let value: Bytes? = try transaction.get(key: keySync)
                    try transaction.commitSync()
                    return value
                }
                try! resultSync.append(resultValue!.cast())
                if resultSync.count == etalon.count {
                    semaphoreSync.signal()
                }
            }
            let _: EventLoopFuture<Void> = FDBTests.fdb
                .withTransaction(on: group.next()) { transaction in
                    return transaction
                        .atomic(.add, key: keyAsync, value: Int64(1))
                        .flatMap { (transaction: AnyFDBTransaction) in
                            return transaction.get(key: keyAsync, commit: true)
                        }
                        .map { (bytes: Bytes?, transaction: AnyFDBTransaction) -> Void in
                            let value: Int64 = try! bytes!.cast()
                            resultAsync.append(value)
                            if resultAsync.count == etalon.count {
                                semaphoreAsync.signal()
                            }
                            return
                        }
                }
        }

        let _ = semaphoreSync.wait(for: 10)
        XCTAssertEqual(resultSync.sorted(), etalon)

        let _ = semaphoreAsync.wait(for: 10)
        XCTAssertEqual(resultAsync.sorted(), etalon)
    }

    func testGetSetReadVersionSync() throws {
        let key = FDBTests.subspace["getSetVersionSync"]
        let etalon = Bytes([1,2,3])

        try FDBTests.fdb.set(key: key, value: etalon)

        let version: Int64 = try FDBTests.fdb!.withTransaction { transaction in
            let _: Bytes? = try transaction.get(key: key)
            return try transaction.getReadVersion()
        }

        let _ = try FDBTests.fdb.withTransaction { transaction in
            XCTAssertNoThrow(transaction.setReadVersion(version: version))
            XCTAssertNoThrow(try transaction.get(key: key) as Bytes?)
        }
    }

    func testGetSetReadVersionNIO() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }

        let key = FDBTests.subspace["getSetReadVersionNIO"]
        let etalon = Bytes([1,2,3])

        try FDBTests.fdb.set(key: key, value: etalon)

        let version: Int64 = try FDBTests.fdb.withTransaction(on: group.next()) { transaction in
            transaction
                .get(key: key)
                .flatMap { (_: Bytes?) in transaction.getReadVersion() }
        }.wait()

        let _: Bytes? = try FDBTests.fdb!.withTransaction(on: group.next()) { transaction in
            transaction.setReadVersion(version: version)
            return transaction.get(key: key)
        }.wait()
    }

    func testBugTransactionCancelled() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }

        // This problem appeared when there are no externals refs to FDB.Transaction instance.
        // Quite rare case tbh, but extremely confusing.
        // Fixed by implicit FDB.Transaction ref capturing in FDB.Future

        XCTAssertNoThrow(
            try FDBTests.fdb.begin(on: group.next())
                .flatMap { transaction in transaction.set(key: FDBTests.subspace["trcancelled"], value: Bytes([1,2,3])) }
                .flatMap { transaction in transaction.commit() }
                .wait()
        )
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
        ("testTransactionOptions", testTransactionOptions),
        ("testNetworkOptions", testNetworkOptions),
        ("testWrappedTransactions", testWrappedTransactions),
        ("testGetSetReadVersionSync", testGetSetReadVersionSync),
        ("testGetSetReadVersionNIO", testGetSetReadVersionNIO),
        ("testBugTransactionCancelled", testBugTransactionCancelled),
    ]
}
