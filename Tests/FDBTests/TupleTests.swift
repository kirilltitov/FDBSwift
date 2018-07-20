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
        let tuple = Tuple(Tuple("foo\u{00}bar", nil, Tuple()))
        var expected = Bytes()
        expected.append(0x05)

        // This should be `0x01` according to tuple doc
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
        expected.append(0xff)
        expected.append(0x05)
        expected.append(0x00)
        expected.append(0x00)
        XCTAssertEqual(tuple.pack(), expected)
    }

    func testPackInts() {
        let cases: [Int: Bytes] = [
            // These ints aren't supported. Yet. Or ever. No idea.
            //-100000000000000000322: [11, 246, 250, 148, 56, 161, 210, 156, 239, 254, 189],
            //-10000000000000000322: [12, 117, 56, 220, 251, 118, 23, 254, 189],
            //-1000000000000000322: [12, 242, 31, 73, 76, 88, 155, 254, 189],
            //-100000000000000322: [12, 254, 156, 186, 135, 162, 117, 254, 189],
            -10000000000000322: [13, 220, 121, 13, 144, 62, 254, 189],
            -1000000000000322: [13, 252, 114, 129, 91, 57, 126, 189],
            -100000000000322: [14, 165, 12, 239, 133, 190, 189],
            -10000000000322: [14, 246, 231, 177, 141, 94, 189],
            -1000000000322: [15, 23, 43, 90, 238, 189],
            -100000000322: [15, 232, 183, 137, 22, 189],
            -10000000322: [15, 253, 171, 244, 26, 189],
            -1000000322: [16, 196, 101, 52, 189],
            -100000322: [16, 250, 10, 29, 189],
            -10000322: [17, 103, 104, 61],
            -1000322: [17, 240, 188, 125],
            -100322: [17, 254, 120, 29],
            -10322: [18, 215, 173],
            -1322: [18, 250, 213],
            -322: [18, 254, 189],
            -22: [19, 233],
            -2: [19, 253],
            0: [20],
            2: [21, 2],
            22: [21, 22],
            322: [22, 1, 66],
            1322: [22, 5, 42],
            10322: [22, 40, 82],
            100322: [23, 1, 135, 226],
            1000322: [23, 15, 67, 130],
            10000322: [23, 152, 151, 194],
            100000322: [24, 5, 245, 226, 66],
            1000000322: [24, 59, 154, 203, 66],
            10000000322: [25, 2, 84, 11, 229, 66],
            100000000322: [25, 23, 72, 118, 233, 66],
            1000000000322: [25, 232, 212, 165, 17, 66],
            10000000000322: [26, 9, 24, 78, 114, 161, 66],
            100000000000322: [26, 90, 243, 16, 122, 65, 66],
            1000000000000322: [27, 3, 141, 126, 164, 198, 129, 66],
            10000000000000322: [27, 35, 134, 242, 111, 193, 1, 66],
            //100000000000000322: [28, 1, 99, 69, 120, 93, 138, 1, 66],
            //1000000000000000322: [28, 13, 224, 182, 179, 167, 100, 1, 66],
            //10000000000000000322: [28, 138, 199, 35, 4, 137, 232, 1, 66],
            //100000000000000000322: [29, 9, 5, 107, 199, 94, 45, 99, 16, 1, 66],
        ]
        for (input, expected) in cases {
            XCTAssertEqual(input.pack(), expected)
        }
    }

    func testUnofficialCases() {
        var expected = Bytes()
        expected.append(contentsOf: [0x13, 0xfe, 0x14, 0x15, 0x05, 0x05, 0x02])
        expected.append(contentsOf: "foo".bytes)
        expected.append(contentsOf: [0x00, 0x00, 0x00])
        XCTAssertEqual(Tuple(-1, 0, 5, Tuple("foo"), nil).pack(), expected)
    }

    static var allTests = [
        ("testPackUnicodeString", testPackUnicodeString),
        ("testPackBinaryString", testPackBinaryString),
        ("testPackNestedTuple", testPackNestedTuple),
        ("testPackInts", testPackInts),
    ]
}
