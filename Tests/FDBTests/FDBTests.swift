@testable import FDB
import XCTest
import LGNLog

class FDBTest: XCTestCase {
    static var fdb: FDB!
    static var subspace: FDB.Subspace!

    internal static let subsystemQueue = DispatchQueue(label: "org.swift.XCTest.XCTWaiter.TEMPORARY")

    override class func setUp() {
        super.setUp()
        LoggingSystem.bootstrap(LGNLogger.init)
        LGNLogger.logLevel = .debug
        LGNLogger.hideTimezone = true
        LGNLogger.hideLabel = true
        LGNLogger.requestIDKey = "trid"
        self.fdb = FDB()
        self.subspace = FDB.Subspace("test \(Int.random(in: 0 ..< Int.max))")
    }

    override class func tearDown() {
        super.tearDown()
//        do {
//            try await self.fdb.clear(subspace: self.subspace)
//        } catch {
//            XCTFail("Could not tearDown: \(error)")
//        }
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
        XCTAssertNoThrow(try Self.fdb.connect())
    }

    func testEmptyValue() async throws {
        let result = try await Self.fdb.get(key: Self.subspace[FDB.Null()])
        XCTAssertNil(result, "Non-nil value returned")
    }

    func testSetGetBytes() async throws {
        let key = Self.subspace["set"]
        let value = self.getRandomBytes()
        try await Self.fdb.set(key: key, value: value)
        let actual = try await Self.fdb.get(key: key)
        XCTAssertEqual(actual, value)
    }

    func testTransaction() async throws {
        let key = Self.subspace["transaction"]
        let expected = self.getRandomBytes()
        let transaction = try Self.fdb.begin() as! FDB.Transaction
        transaction.set(key: key, value: expected)
        let actual = try await transaction.get(key: key)
        XCTAssertEqual(actual, expected)
        try await transaction.commit()
        // transaction is already closed
        do {
            try await transaction.commit()
            XCTFail("Should have thrown")
        } catch {}
    }

    func testGetRange() async throws {
        let limit = 2
        let subspace = Self.subspace["range"]
        var values: [FDB.KeyValue] = []
        for i in 0 ..< limit {
            let key = subspace["sub \(i)"].asFDBKey()
            let value = self.getRandomBytes()
            values.append(FDB.KeyValue(key: key, value: value))
            try await Self.fdb.set(key: key, value: value)
        }
        let expected = FDB.KeyValuesResult(records: values, hasMore: false)
        let actual1 = try await Self.fdb.get(subspace: subspace)
        XCTAssertEqual(actual1, expected)
        let actual2 = try await Self.fdb.get(range: subspace.range)
        XCTAssertEqual(actual2, expected)
        let actual3 = try await Self.fdb.get(begin: subspace.range.begin, end: subspace.range.end)
        XCTAssertEqual(actual3, expected)
    }

    func testGetRangeAllBatches() async throws {
        let subspace = Self.subspace["range_batches"]
        let count = 1000
        let value = Bytes(repeating: 0x42, count: 1024)

        // A subspace-like neighbour right before the range: must never leak into results
        try await Self.fdb.set(key: Self.subspace["range_batche"].asFDBKey() + [0xFF], value: value)

        try await Self.fdb.withTransaction { transaction in
            for i in 0 ..< count {
                transaction.set(key: subspace[i], value: value)
            }
            try await transaction.commit()
        }

        let result = try await Self.fdb.get(subspace: subspace)
        XCTAssertEqual(result.records.count, count)
        XCTAssertFalse(result.hasMore)
        XCTAssertEqual(result.records.first?.key, subspace[0].asFDBKey())
        XCTAssertEqual(result.records.last?.key, subspace[count - 1].asFDBKey())
    }

    func testNonASCIIKeysWithDebugLogging() async throws {
        var logger = Logger(label: "test")
        logger.logLevel = .trace

        try await Logger.$current.withValue(logger) {
            let key = Self.subspace["non-ascii", UUID(), -42, Float(3.14), "ключ"]
            let expected: Bytes = [0x00, 0x7F, 0x80, 0xFF]
            try await Self.fdb.set(key: key, value: expected)
            try await Self.fdb.atomic(.bitOr, key: key, value: expected)
            let actual = try await Self.fdb.get(key: key)
            XCTAssertEqual(actual, expected)
            _ = try await Self.fdb.get(subspace: Self.subspace["non-ascii"])
        }
    }

    func testWithTransactionRetryLimit() async throws {
        var attempts = 0
        do {
            let _: Void = try await Self.fdb.withTransaction(retryLimit: 3) { _ in
                attempts += 1
                throw FDB.Error.transactionRetry
            }
            XCTFail("Should have thrown")
        } catch FDB.Error.transactionRetryLimitExceeded {
            XCTAssertEqual(attempts, 4)
        }
    }

    func testDoubleDestroy() throws {
        let transaction = try Self.fdb.begin()
        transaction.destroy()
        transaction.destroy()
    }

    func testNetworkOptionRedaction() {
        XCTAssertEqual(
            FDB.NetworkOption.TLSKeyBytes(bytes: Bytes("SECRET".utf8)).redactedDescription,
            "TLSKeyBytes(<private>)"
        )
        XCTAssertFalse(FDB.NetworkOption.TLSPassword(password: "SECRET").redactedDescription.contains("SECRET"))
        XCTAssertEqual(FDB.NetworkOption.TLSCABytes(bytes: [1, 2, 3]).redactedDescription, "TLSCABytes(<3 bytes>)")
        XCTAssertEqual(
            FDB.NetworkOption.traceLogGroup(name: "foo").redactedDescription,
            "traceLogGroup(name: \"foo\")"
        )
    }

    func testAtomicAdd() async throws {
        let fdb = Self.fdb!
        let key = Self.subspace.subspace("atomic_incr")
        let step: Int64 = 1
        let expected = step + 1
        for _ in 0 ..< expected - 1 {
            try await fdb.atomic(.add, key: key, value: step)
        }
        let actual1 = try await fdb.increment(key: key)
        XCTAssertNoThrow(actual1)
        let result = try await fdb.get(key: key)
        XCTAssertNotNil(result)
        try XCTAssertEqual(result!.cast() as Int64, expected)
        XCTAssertEqual(result, getBytes(expected))
        let actual2 = try await fdb.increment(key: key)
        XCTAssertEqual(actual2, expected + 1)
        let actual3 = try await fdb.increment(key: key, value: -1)
        XCTAssertEqual(actual3, expected)
        let actual4 = try await fdb.decrement(key: key)
        XCTAssertEqual(actual4, expected - 1)
        let actual5 = try await fdb.decrement(key: key)
        XCTAssertEqual(actual5, 0)
    }

    func testSetVersionstampedKey() async throws {
        let fdb = Self.fdb!
        let subspace = Self.subspace.subspace("atomic_versionstamp")

        do {
            Logger.current.info("Testing synchronous variations")
            let value: String = "basic sync value"
            let nonVersionstampedKey = subspace[FDB.Versionstamp(transactionCommitVersion: 1, batchNumber: 2)]["aSyncKey"]

            let versionStamp: FDB.Versionstamp = try await fdb.withTransaction { transaction in
                XCTAssertNoThrow(try transaction.set(versionstampedKey: subspace[FDB.Versionstamp()]["aSyncKey"], value: Bytes(value.utf8)) as Void)
                XCTAssertThrowsError(try transaction.set(versionstampedKey: nonVersionstampedKey, value: getBytes(value.utf8)) as Void) { error in
                    switch error {
                    case FDB.Error.missingIncompleteVersionstamp: break
                    default: XCTFail("Invalid error returned: \(error)")
                    }
                }

                return try await transaction.getVersionstamp()
            }

            XCTAssertNil(versionStamp.userData)

            let result = try await fdb.get(key: subspace[versionStamp]["aSyncKey"])
            XCTAssertEqual(String(bytes: result ?? [], encoding: .utf8), value)
            Logger.current.info("Finished testing synchronous variations")
        }

        do {
            Logger.current.info("Testing synchronous variations, with userData and multiple writes")
            let valueA: String = "advanced sync value A"
            let valueB: String = "advanced sync value B"

            var versionStamp: FDB.Versionstamp = try await fdb.withTransaction { transaction in
                try transaction.set(versionstampedKey: subspace[FDB.Versionstamp(userData: 1)]["aSyncKey"], value: Bytes(valueA.utf8)) as Void
                try transaction.set(versionstampedKey: subspace[FDB.Versionstamp(userData: 2)]["aSyncKey"], value: Bytes(valueB.utf8)) as Void
                return try await transaction.getVersionstamp()
            }

            XCTAssertNil(versionStamp.userData)

            versionStamp.userData = 1
            let resultA = try await fdb.get(key: subspace[versionStamp]["aSyncKey"])
            XCTAssertEqual(String(bytes: resultA ?? [], encoding: .utf8), valueA)

            versionStamp.userData = 2
            let resultB = try await fdb.get(key: subspace[versionStamp]["aSyncKey"])
            XCTAssertEqual(String(bytes: resultB ?? [], encoding: .utf8), valueB)
            Logger.current.info("Finished testing synchronous variations, with userData and multiple writes")
        }
    }

    func testClear() async throws {
        try await Self.fdb.clear(key: Self.subspace["empty"])
    }

    func testStringKeys() async throws {
        let fdb = Self.fdb!
        let key = "foo"
        let expected: Bytes = [0, 1, 2]
        try await fdb.set(key: Self.subspace[key], value: expected)
        let actual = try await fdb.get(key: Self.subspace[key])
        XCTAssertEqual(actual, expected)
    }

    func testStaticStringKeys() async throws {
        let fdb = Self.fdb!
        let key: StaticString = "foo"
        let expected: Bytes = [0, 1, 2]
        try await fdb.set(key: Self.subspace[key], value: expected)
        let actual = try await fdb.get(key: Self.subspace[key])
        XCTAssertEqual(actual, expected)
    }

    func testErrorDescription() {
        typealias E = FDB.Error
        XCTAssertEqual(E.transactionReadOnly.errno, 2021)
        XCTAssertEqual(E.transactionReadOnly.getDescription(), "Transaction is read-only and therefore does not have a commit version")
        XCTAssertEqual(E.unexpectedError("FOo bar").getDescription(), "Error is unexpected, it shouldn't really happen")
    }

    func testFailingCommit() async throws {
        let tr = try Self.fdb.begin()
        try await tr.commit()
        do {
            try await tr.commit()
        } catch {
            guard case FDB.Error.usedDuringCommit = error else {
                XCTFail("Error must be UsedDuringCommit")
                return
            }
        }
    }

    func testTransactionOptions() async throws {
        let tr = try Self.fdb.begin() as! FDB.Transaction
        let key = Self.subspace["troptions"]
        try tr.setOption(.debugRetryLogging(transactionName: "testtransactionname"))
        try tr.setOption(.transactionLoggingEnable(identifier: "identifier"))
        try tr.setOption(.timeout(milliseconds: 1000))
        try tr.setOption(.retryLimit(retries: 4))
        try tr.setOption(.maxRetryDelay(milliseconds: 5000))
        tr.set(key: key, value: Bytes([1,2,3]))
        let actual = try await tr.get(key: key)
        XCTAssertEqual(Bytes([1,2,3]), actual)
        try await tr.commit()
    }

    func testNetworkOptions() async throws {
//        6.3.18 still not fixed zzzzz
//        XCTAssertThrowsError(try Self.fdb.setOption(.TLSCertPath(path: "/tmp/invalidname")))
//        XCTAssertThrowsError(try Self.fdb.setOption(.TLSCABytes(bytes: Bytes([1,2,3]))))
        try Self.fdb.setOption(.TLSVerifyPeers(string: "Check.Valid=0"))
        try Self.fdb.setOption(.TLSPassword(password: "some secret password"))
        try Self.fdb.setOption(.buggifyDisable)
        try Self.fdb.setOption(.buggifySectionActivatedProbability(probability: 0))
    }

    func testWrappedTransactions() async throws {
        class Res: @unchecked Sendable {
            var arr = [Int64]()
        }

        let sample: [Int64] = (1...100).map { $0 }
        let res = Res()
        let semaphore = DispatchSemaphore(value: 0)
        let keySync = Self.subspace["increment_sync"]

        try await Self.fdb.clear(key: keySync)

        for _ in sample {
            Task {
                let resultValue: Bytes? = try! await Self.fdb.withTransaction { transaction in
                    transaction.atomic(.add, key: keySync, value: Int64(1))
                    let value: Bytes? = try await transaction.get(key: keySync)
                    try await transaction.commit()
                    return value
                }
                try! res.arr.append(resultValue!.cast())
                if res.arr.count == sample.count {
                    semaphore.signal()
                }
            }
        }

        let _ = semaphore.wait(for: 10)
        XCTAssertEqual(res.arr.sorted(), sample)
    }

    func testGetSetReadVersionSync() async throws {
        let key = Self.subspace["getSetVersionSync"]
        let sample = Bytes([1,2,3])

        try await Self.fdb.set(key: key, value: sample)

        let version: Int64 = try await Self.fdb.withTransaction { transaction in
            let _: Bytes? = try await transaction.get(key: key)
            return try await transaction.getReadVersion()
        }

        _ = try await Self.fdb.withTransaction { transaction in
            transaction.setReadVersion(version: version)
            _ = try await transaction.get(key: key)
        }
    }
}
