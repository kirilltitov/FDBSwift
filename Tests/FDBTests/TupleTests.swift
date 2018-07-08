import XCTest
@testable import FDB

class TupleTests: XCTestCase {
    func testPackUnicodeString() {
        var expected = Bytes()
        expected.append(0x02)
        expected.append(contentsOf: "F".bytes)
        expected.append(0xC3)
        expected.append(0x94)
        expected.append(contentsOf: "O".bytes)
        expected.append(0x00)
        expected.append(0xFF)
        expected.append(contentsOf: "bar".bytes)
        expected.append(0x00)
        XCTAssertEqual("F\u{00d4}O\u{0000}bar".pack(), expected)
    }

    func testPackBinaryString() {
        var expected: Bytes = []
        expected.append(0x01)
        expected.append(contentsOf: "foo".bytes)
        expected.append(0x00)
        expected.append(0xff)
        expected.append(contentsOf: "bar".bytes)
        expected.append(0x00)
        XCTAssertEqual("foo\u{00}bar".bytes.pack(), expected)
    }

    func testPackNestedTuple() {
        let tuple = Tuple("foo\u{00}bar", nil, Tuple())
        var expected = Bytes()

        // This should be `0x01` according to tuple dock
        // (see https://github.com/apple/foundationdb/blob/master/design/tuple.md#nested-tuple)
        // HOWEVER Swift can't make a difference between ASCII and UTF strings,
        // so I decided to use only UTF strings in tuples.
        // Byte string packing, on the other hand, is only used for byte arrays
        expected.append(0x02)
        expected.append(contentsOf: "foo".bytes)
        expected.append(0x00)
        expected.append(0xff)
        expected.append(contentsOf: "bar".bytes)
        expected.append(0x00)
        expected.append(0x00)
        expected.append(0x05)
        expected.append(0x00)
        print(tuple.pack())
        print(expected)
        XCTAssertEqual(tuple.pack(), expected)
    }

    static var allTests = [
        ("testPackUnicodeString", testPackUnicodeString),
        ("testPackBinaryString", testPackBinaryString),
        ("testPackNestedTuple", testPackNestedTuple),
    ]
}
