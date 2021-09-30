import XCTest

#if !canImport(ObjectiveC)

extension FDBTest {
    static let __allTests__FDBTest = [
        ("testEmptyValue", asyncTest(testEmptyValue)),
        ("testSetGetBytes", asyncTest(testSetGetBytes)),
        ("testTransaction", asyncTest(testTransaction)),
        ("testGetRange", asyncTest(testGetRange)),
        ("testAtomicAdd", asyncTest(testAtomicAdd)),
        ("testSetVersionstampedKey", asyncTest(testSetVersionstampedKey)),
        ("testClear", asyncTest(testClear)),
        ("testStringKeys", asyncTest(testStringKeys)),
        ("testStaticStringKeys", asyncTest(testStaticStringKeys)),
        ("testErrorDescription", testErrorDescription),
        ("testFailingCommit", asyncTest(testFailingCommit)),
        ("testTransactionOptions", asyncTest(testTransactionOptions)),
        ("testNetworkOptions", asyncTest(testNetworkOptions)),
        ("testWrappedTransactions", asyncTest(testWrappedTransactions)),
        ("testGetSetReadVersionSync", asyncTest(testGetSetReadVersionSync)),
    ]
}

extension TupleTests {
    static let __allTests__TupleTests = [
        ("testPackUnicodeString", testPackUnicodeString),
        ("testPackBinaryString", testPackBinaryString),
        ("testPackNestedTuple", testPackNestedTuple),
        ("testPackInts", testPackInts),
        ("testUnofficialCases", testUnofficialCases),
        ("testUnpack", testUnpack),
        ("testNullEscapes", testNullEscapes),
        ("testUnpackSanity", testUnpackSanity),
        ("testFloat", testFloat),
        ("testDouble", testDouble),
        ("testBool", testBool),
        ("testUUID", testUUID),
        ("testVersionstamp", testVersionstamp),
        ("testIncompleteVersionstampDetection", testIncompleteVersionstampDetection)
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    [
        testCase(FDBTest.__allTests__FDBTest),
        testCase(TupleTests.__allTests__TupleTests),
    ]
}

#endif
