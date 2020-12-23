@testable import FDB
import XCTest

class TupleTests: XCTestCase {
    override func setUp() {
        FDB.logger.logLevel = .critical
    }

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
        expected.append(0xFF)
        expected.append(contentsOf: "bar".bytes)
        expected.append(0x00)
        XCTAssertEqual("foo\u{00}bar".bytes.pack(), expected)
    }

    func testPackNestedTuple() {
        let tuple = FDB.Tuple(FDB.Tuple("foo\u{00}bar", FDB.Null(), FDB.Tuple()))
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
        expected.append(0xFF)
        expected.append(contentsOf: "bar".bytes)
        expected.append(0x00)
        expected.append(0x00)
        expected.append(0xFF)
        expected.append(0x05)
        expected.append(0x00)
        expected.append(0x00)
        XCTAssertEqual(tuple.pack(), expected)
    }

    func testPackInts() {
        let cases: [Int: Bytes] = [
            // These ints aren't supported. Yet. Or ever. No idea.
            // -100000000000000000322: [11, 246, 250, 148, 56, 161, 210, 156, 239, 254, 189],
            // -10000000000000000322: [12, 117, 56, 220, 251, 118, 23, 254, 189],
            // -1000000000000000322: [12, 242, 31, 73, 76, 88, 155, 254, 189],
            // -100000000000000322: [12, 254, 156, 186, 135, 162, 117, 254, 189],
            -10_000_000_000_000_322: [13, 220, 121, 13, 144, 62, 254, 189],
            -1_000_000_000_000_322: [13, 252, 114, 129, 91, 57, 126, 189],
            -100_000_000_000_322: [14, 165, 12, 239, 133, 190, 189],
            -10_000_000_000_322: [14, 246, 231, 177, 141, 94, 189],
            -1_000_000_000_322: [15, 23, 43, 90, 238, 189],
            -100_000_000_322: [15, 232, 183, 137, 22, 189],
            -10_000_000_322: [15, 253, 171, 244, 26, 189],
            -1_000_000_322: [16, 196, 101, 52, 189],
            -100_000_322: [16, 250, 10, 29, 189],
            -10_000_322: [17, 103, 104, 61],
            -1_000_322: [17, 240, 188, 125],
            -100_322: [17, 254, 120, 29],
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
            100_322: [23, 1, 135, 226],
            1_000_322: [23, 15, 67, 130],
            10_000_322: [23, 152, 151, 194],
            100_000_322: [24, 5, 245, 226, 66],
            1_000_000_322: [24, 59, 154, 203, 66],
            10_000_000_322: [25, 2, 84, 11, 229, 66],
            100_000_000_322: [25, 23, 72, 118, 233, 66],
            1_000_000_000_322: [25, 232, 212, 165, 17, 66],
            10_000_000_000_322: [26, 9, 24, 78, 114, 161, 66],
            100_000_000_000_322: [26, 90, 243, 16, 122, 65, 66],
            1_000_000_000_000_322: [27, 3, 141, 126, 164, 198, 129, 66],
            10_000_000_000_000_322: [27, 35, 134, 242, 111, 193, 1, 66],
            // 100000000000000322: [28, 1, 99, 69, 120, 93, 138, 1, 66],
            // 1000000000000000322: [28, 13, 224, 182, 179, 167, 100, 1, 66],
            // 10000000000000000322: [28, 138, 199, 35, 4, 137, 232, 1, 66],
            // 100000000000000000322: [29, 9, 5, 107, 199, 94, 45, 99, 16, 1, 66],
        ]
        for (input, expected) in cases {
            XCTAssertEqual(input.pack(), expected)
        }
    }

    func testUnofficialCases() {
        var expected = Bytes()
        expected.append(contentsOf: [0x13, 0xFE, 0x14, 0x15, 0x05, 0x05, 0x02])
        expected.append(contentsOf: "foo".bytes)
        expected.append(contentsOf: [0x00, 0x00, 0x00])
        XCTAssertEqual(FDB.Tuple(-1, 0, 5, FDB.Tuple("foo"), FDB.Null()).pack(), expected)
    }

    func testUnpack() throws {
        let input: [FDBTuplePackable] = [
            Bytes([0, 1, 2]),
            322,
            -322,
            FDB.Null(),
            "foo",
            UUID(),
            true,
            FDB.Tuple("bar", 1337, UUID(), Float(3.14), Double(322.1337), "baz", true, true, true, false),
            FDB.Tuple(FDB.Tuple(FDB.Tuple())),
            FDB.Tuple(Double(1637.1711)),
            Float(3.14),
            false,
            FDB.Null(),
            "foo\u{00}bar",
            FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 42),
            FDB.Versionstamp(userData: 73),
        ]
        let etalonTuple = FDB.Tuple(input)
        let packed = etalonTuple.pack()
        let repacked = try FDB.Tuple(from: packed).pack()
        XCTAssertEqual(packed, repacked)
    }

    // Fixes https://github.com/kirilltitov/FDBSwift/issues/10
    func testNullEscapes() throws {
        let packed = Bytes([0, 0, 0,]).pack()
        let repacked = try FDB.Tuple(from: packed).pack()
        XCTAssertEqual(packed, repacked)
    }

    func testUnpackSanity() {
        for _ in 1...10000 {
            do {
                let _ = try FDB.Tuple(
                    from: (1...UInt8.random(in: 10..<UInt8.max)).map { _ in UInt8.random(in: 0..<UInt8.max) }
                )
            } catch {}
        }
    }

    func testFloat() throws {
        for _ in 0...1000 {
            let random = Float32.random(in: -1000...1000)
            let packed = random.pack()
            let unpacked = try FDB.Tuple(from: packed)
            XCTAssertEqual(random, unpacked.tuple[0] as! Float)
            let repacked = unpacked.pack()
            XCTAssertEqual(packed, repacked)
        }

        let cases: [(Float32, Bytes)] = [
            (-10000.01, [32, 57, 227, 191, 245]),
            (-6500.1235, [32, 58, 52, 223, 2]),
            (-100.00001, [32, 61, 55, 255, 254]),
            (-1.0, [32, 64, 127, 255, 255]),
            (0.0, [32, 128, 0, 0, 0]),
            (-0.0, [32, 127, 255, 255, 255]),
            (1.0, [32, 191, 128, 0, 0]),
            (1.1, [32, 191, 140, 204, 205]),
            (3.14, [32, 192, 72, 245, 195]),
            (322.1337, [32, 195, 161, 17, 29]),
            (1000.0, [32, 196, 122, 0, 0]),
            (65545.17, [32, 199, 128, 4, 150]),
        ]

        for (inputFloat, expectedBytes) in cases {
            XCTAssertEqual(expectedBytes, inputFloat.pack())
        }
    }

    func testDouble() throws {
        for _ in 0...1000 {
            let random = Double.random(in: -1000...1000)
            let packed = random.pack()
            let unpacked = try FDB.Tuple(from: packed)
            XCTAssertEqual(random, unpacked.tuple[0] as! Double)
            let repacked = unpacked.pack()
            XCTAssertEqual(packed, repacked)
        }

        let cases: [(Double, Bytes)] = [
            (-10000.01, [33, 63, 60, 119, 254, 184, 81, 235, 132]),
            (-6500.1234, [33, 63, 70, 155, 224, 104, 219, 139, 171]),
            (-100.00001, [33, 63, 166, 255, 255, 214, 14, 148, 237]),
            (-1.0, [33, 64, 15, 255, 255, 255, 255, 255, 255]),
            (0.0, [33, 128, 0, 0, 0, 0, 0, 0, 0]),
            (-0.0, [33, 127, 255, 255, 255, 255, 255, 255, 255]),
            (1.0, [33, 191, 240, 0, 0, 0, 0, 0, 0]),
            (1.1, [33, 191, 241, 153, 153, 153, 153, 153, 154]),
            (3.14, [33, 192, 9, 30, 184, 81, 235, 133, 31]),
            (3.141592653589793, [33, 192, 9, 33, 251, 84, 68, 45, 24]),
            (322.1337, [33, 192, 116, 34, 35, 162, 156, 119, 154]),
            (1000.0, [33, 192, 143, 64, 0, 0, 0, 0, 0]),
            (65545.17111337, [33, 192, 240, 0, 146, 188, 225, 95, 129]),
        ]

        for (inputFloat, expectedBytes) in cases {
            XCTAssertEqual(expectedBytes, inputFloat.pack())
        }
    }

    func testBool() throws {
        XCTAssertEqual([0x26], false.pack())
        XCTAssertEqual([0x27], true.pack())

        for bool in [true, false] {
            let packed = bool.pack()
            let unpacked = try FDB.Tuple(from: packed)
            XCTAssertEqual(bool, unpacked.tuple[0] as! Bool)
            let repacked = unpacked.pack()
            XCTAssertEqual(packed, repacked)
        }
    }

    func testUUID() throws {
        let etalon: uuid_t = (136,167,235,150,108,115,69,118,164,45,145,99,222,237,56,59)
        let uuid = UUID(uuid: etalon)
        let packed = uuid.pack()
        XCTAssertEqual([0x30] + getBytes(etalon), packed)
        let unpacked = try FDB.Tuple(from: packed)
        XCTAssertEqual(uuid, unpacked.tuple[0] as! UUID)
        XCTAssertEqual(packed, unpacked.pack())
    }
    
    func testVersionstamp() throws {
        let cases: [(FDB.Versionstamp, Bytes)] = [
            (FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 196), [50, 00, 00, 00, 00, 00, 00, 00, 42, 00, 196]),
            (FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 196, userData: nil), [50, 00, 00, 00, 00, 00, 00, 00, 42, 00, 196]),
            (FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 196, userData: 0), [51, 00, 00, 00, 00, 00, 00, 00, 42, 00, 196, 00, 00]),
            (FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 196, userData: 24), [51, 00, 00, 00, 00, 00, 00, 00, 42, 00, 196, 00, 24]),
            (FDB.Versionstamp(), [50, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
            (FDB.Versionstamp(userData: nil), [50, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
            (FDB.Versionstamp(userData: 0), [51, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 00, 00]),
            (FDB.Versionstamp(userData: 24), [51, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 00, 24]),
        ]

        for (input, expectedBytes) in cases {
            XCTAssertEqual(expectedBytes, input.pack())
            let unpacked = try FDB.Tuple(from: expectedBytes)
            XCTAssertEqual(input, unpacked.tuple[0] as! FDB.Versionstamp)
        }
    }
    
    func testIncompleteVersionstampDetection() throws {
        let cases: [(Bytes, UInt32)] = [
            (FDB.Tuple(FDB.Versionstamp()).pack(), 1),
            (FDB.Tuple(FDB.Versionstamp(userData: 0)).pack(), 1),
            (FDB.Tuple("foo", FDB.Versionstamp()).pack(), 6),
            (FDB.Tuple("foo", FDB.Versionstamp(userData: 0)).pack(), 6),
            (FDB.Tuple("foo", FDB.Versionstamp(), FDB.Versionstamp()).pack(), 6),
            (FDB.Tuple("foo", FDB.Versionstamp(transactionCommitVersion: 12, batchNumber: 0), FDB.Versionstamp(), FDB.Versionstamp()).pack(), 17),
            (FDB.Tuple("foo", FDB.Versionstamp(transactionCommitVersion: 0, batchNumber: 12), FDB.Versionstamp(), FDB.Versionstamp()).pack(), 17),
            (FDB.Tuple("foo", FDB.Tuple(FDB.Versionstamp())).pack(), 7),
            (FDB.Tuple("foo", FDB.Tuple(FDB.Versionstamp()), FDB.Versionstamp()).pack(), 7),
            (FDB.Tuple("foo", FDB.Tuple("bar", FDB.Versionstamp()), FDB.Versionstamp()).pack(), 12),
        ]

        for (packedInput, offset) in cases {
            let actualOffset = try FDB.Tuple.offsetOfFirstIncompleteVersionstamp(from: packedInput)
            XCTAssertEqual(offset, actualOffset, "\(packedInput) version stamp offset was at \(actualOffset), not \(offset)")
        }
        
        let invalidCases: [Bytes] = [
            FDB.Tuple().pack(),
            FDB.Tuple(42, "foo").pack(),
            FDB.Tuple(FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 0)).pack(),
            FDB.Tuple(FDB.Versionstamp(transactionCommitVersion: 0, batchNumber: 12)).pack(),
            FDB.Tuple(FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 12, userData: 0)).pack(),
            FDB.Tuple(42, "foo", FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 0)).pack(),
            FDB.Tuple(42, "foo", FDB.Versionstamp(transactionCommitVersion: 0, batchNumber: 12)).pack(),
            FDB.Tuple(42, "foo", FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 12, userData: 0)).pack(),
        ]

        for packedInput in invalidCases {
            XCTAssertThrowsError(try FDB.Tuple.offsetOfFirstIncompleteVersionstamp(from: packedInput)) { error in
                XCTAssertEqual((error as! FDB.Error).errno, FDB.Error.missingIncompleteVersionstamp.errno)
            }
        }
    }
}
