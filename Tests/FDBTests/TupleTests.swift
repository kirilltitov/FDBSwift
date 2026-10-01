@testable import FDB
import Foundation
import Testing

@Suite("Tuple")
struct TupleTests {
    @Test func packUnicodeString() {
        let expected: Bytes = [0x02] + Bytes("F".utf8) + [0xC3, 0x94] + Bytes("O".utf8) + [0x00, 0xFF] + Bytes("bar".utf8) + [0x00]
        #expect(FDB.Tuple("F\u{00d4}O\u{0000}bar").packed == expected)
    }

    @Test func packBinaryString() {
        let expected: Bytes = [0x01] + Bytes("foo".utf8) + [0x00, 0xFF] + Bytes("bar".utf8) + [0x00]
        #expect(FDB.Tuple(Bytes("foo\u{00}bar".utf8)).packed == expected)
    }

    @Test func packNestedTuple() {
        let tuple = FDB.Tuple(FDB.Tuple("foo\u{00}bar", FDB.Null(), FDB.Tuple()))
        let expected: Bytes = [0x05, 0x02] + Bytes("foo".utf8) + [0x00, 0xFF] + Bytes("bar".utf8)
            + [0x00, 0x00, 0xFF, 0x05, 0x00, 0x00]
        #expect(tuple.packed == expected)
    }

    @Test(arguments: [
        (Int64.min, [12, 127, 255, 255, 255, 255, 255, 255, 255]),
        (-100_000_000_000_000_322, [12, 254, 156, 186, 135, 162, 117, 254, 189]),
        (-10_000_000_000_000_322, [13, 220, 121, 13, 144, 62, 254, 189]),
        (-1_000_000_000_000_322, [13, 252, 114, 129, 91, 57, 126, 189]),
        (-100_000_000_000_322, [14, 165, 12, 239, 133, 190, 189]),
        (-10_000_000_000_322, [14, 246, 231, 177, 141, 94, 189]),
        (-1_000_000_000_322, [15, 23, 43, 90, 238, 189]),
        (-100_000_000_322, [15, 232, 183, 137, 22, 189]),
        (-10_000_000_322, [15, 253, 171, 244, 26, 189]),
        (-1_000_000_322, [16, 196, 101, 52, 189]),
        (-100_000_322, [16, 250, 10, 29, 189]),
        (-10_000_322, [17, 103, 104, 61]),
        (-1_000_322, [17, 240, 188, 125]),
        (-100_322, [17, 254, 120, 29]),
        (-10322, [18, 215, 173]),
        (-1322, [18, 250, 213]),
        (-322, [18, 254, 189]),
        (-22, [19, 233]),
        (-2, [19, 253]),
        (0, [20]),
        (2, [21, 2]),
        (22, [21, 22]),
        (322, [22, 1, 66]),
        (1322, [22, 5, 42]),
        (10322, [22, 40, 82]),
        (100_322, [23, 1, 135, 226]),
        (1_000_322, [23, 15, 67, 130]),
        (10_000_322, [23, 152, 151, 194]),
        (100_000_322, [24, 5, 245, 226, 66]),
        (1_000_000_322, [24, 59, 154, 203, 66]),
        (10_000_000_322, [25, 2, 84, 11, 229, 66]),
        (100_000_000_322, [25, 23, 72, 118, 233, 66]),
        (1_000_000_000_322, [25, 232, 212, 165, 17, 66]),
        (10_000_000_000_322, [26, 9, 24, 78, 114, 161, 66]),
        (100_000_000_000_322, [26, 90, 243, 16, 122, 65, 66]),
        (1_000_000_000_000_322, [27, 3, 141, 126, 164, 198, 129, 66]),
        (10_000_000_000_000_322, [27, 35, 134, 242, 111, 193, 1, 66]),
        (100_000_000_000_000_322, [28, 1, 99, 69, 120, 93, 138, 1, 66]),
        (1_000_000_000_000_000_322, [28, 13, 224, 182, 179, 167, 100, 1, 66]),
        (Int64.max, [28, 127, 255, 255, 255, 255, 255, 255, 255]),
    ] as [(Int64, Bytes)])
    func packInts(value: Int64, expected: Bytes) throws {
        #expect(FDB.Tuple(value).packed == expected)
        #expect(try FDB.Tuple(packed: expected).unpack(as: Int64.self) == value)
    }

    @Test func packUInt64() throws {
        let expected: Bytes = [28, 138, 199, 35, 4, 137, 232, 1, 66]
        #expect(FDB.Tuple(UInt64(10_000_000_000_000_000_322)).packed == expected)
        #expect(try FDB.Tuple(packed: expected).unpack(as: UInt64.self) == 10_000_000_000_000_000_322)
        #expect(throws: FDB.Error.unpackTooLargeInt) { try FDB.Tuple(packed: expected).unpack(as: Int.self) }
        #expect(throws: FDB.Error.unpackTooLargeInt) { try FDB.Tuple(-1).unpack(as: UInt.self) }
        #expect(throws: FDB.Error.unpackTooLargeInt) { try FDB.Tuple(300).unpack(as: Int8.self) }
        #expect(try FDB.Tuple(Int8(-5)).unpack(as: Int64.self) == -5)
    }

    @Test func unofficialCases() {
        let expected: Bytes = [0x13, 0xFE, 0x14, 0x15, 0x05, 0x05, 0x02] + Bytes("foo".utf8) + [0x00, 0x00, 0x00]
        #expect(FDB.Tuple(-1, 0, 5, FDB.Tuple("foo"), FDB.Null()).packed == expected)
    }

    @Test func roundTrip() throws {
        let uuid = UUID()
        let tuple = FDB.Tuple(
            Bytes([0, 1, 2]), 322, -322, FDB.Null(), "foo", uuid, true,
            FDB.Tuple("bar", 1337, UUID(), Float(3.14), Double(322.1337), "baz", true, false),
            FDB.Tuple(FDB.Tuple(FDB.Tuple())),
            FDB.Tuple(Double(1637.1711), FDB.Null()),
            Float(3.14), false, FDB.Null(), "foo\u{00}bar",
            FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 42),
            FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 42, userVersion: 73)
        )
        let decoded = try FDB.Tuple(packed: tuple.packed)
        #expect(decoded == tuple)
        #expect(decoded.packed == tuple.packed)
        #expect(FDB.Tuple(elements: decoded.elements) == tuple)
        #expect(decoded.count == 16)
        #expect(decoded.elements[5] == .uuid(uuid))
    }

    @Test func typedUnpack() throws {
        let tuple = FDB.Tuple("user", 42, Optional<String>.none, FDB.Tuple(true, 1.5))
        let (kind, id, missing, nested) = try tuple.unpack(as: String.self, Int.self, String?.self, FDB.Tuple.self)
        #expect(kind == "user")
        #expect(id == 42)
        #expect(missing == nil)
        let (flag, number) = try nested.unpack(as: Bool.self, Double.self)
        #expect(flag)
        #expect(number == 1.5)

        #expect(throws: FDB.Error.unpackTypeMismatch) { try tuple.unpack(as: String.self, Int.self) }
        #expect(throws: FDB.Error.unpackTypeMismatch) { try tuple.unpack(as: Int.self, Int.self, String?.self, FDB.Tuple.self) }
    }

    @Test func appending() {
        #expect(FDB.Tuple("a").appending(1, true) == FDB.Tuple("a", 1, true))
    }

    // Fixes https://github.com/kirilltitov/FDBSwift/issues/10
    @Test func nullEscapes() throws {
        let packed = FDB.Tuple(Bytes([0, 0, 0])).packed
        #expect(try FDB.Tuple(packed: packed).packed == packed)
    }

    @Test func unpackRandomGarbage() {
        // Must never crash
        for _ in 1 ... 10000 {
            _ = try? FDB.Tuple(packed: (0 ..< Int.random(in: 1 ..< 64)).map { _ in UInt8.random(in: 0 ... 255) })
        }
    }

    @Test func unpackTooDeep() {
        let deep = Bytes(repeating: 0x05, count: 100_000)
        #expect(throws: FDB.Error.unpackTooDeep) { try FDB.Tuple(packed: deep) }
        var ok = FDB.Tuple()
        for _ in 0 ..< 32 {
            ok = FDB.Tuple(ok)
        }
        #expect(throws: Never.self) { try FDB.Tuple(packed: ok.packed) }
    }

    @Test func invalidInput() {
        #expect(throws: FDB.Error.unpackInvalidInput) { try FDB.Tuple(packed: [0x05, 0x14]) } // unterminated nested
        #expect(throws: FDB.Error.unpackInvalidInput) { try FDB.Tuple(packed: [0x21, 0x00]) } // truncated double
        #expect(throws: FDB.Error.unpackInvalidString) { try FDB.Tuple(packed: [0x02, 0xFF, 0x00]) }
        #expect(throws: FDB.Error.unpackUnknownCode) { try FDB.Tuple(packed: [0x1D, 0x01]) }
    }

    @Test(arguments: [
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
    ] as [(Float, Bytes)])
    func float(value: Float, expected: Bytes) throws {
        #expect(FDB.Tuple(value).packed == expected)
        #expect(try FDB.Tuple(packed: expected).unpack(as: Float.self).bitPattern == value.bitPattern)
    }

    @Test(arguments: [
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
    ] as [(Double, Bytes)])
    func double(value: Double, expected: Bytes) throws {
        #expect(FDB.Tuple(value).packed == expected)
        #expect(try FDB.Tuple(packed: expected).unpack(as: Double.self).bitPattern == value.bitPattern)
    }

    @Test func randomFloatingPoint() throws {
        for _ in 0 ... 1000 {
            let float = Float.random(in: -1000 ... 1000)
            let double = Double.random(in: -1000 ... 1000)
            let tuple = FDB.Tuple(float, double)
            let (f, d) = try FDB.Tuple(packed: tuple.packed).unpack(as: Float.self, Double.self)
            #expect(f == float)
            #expect(d == double)
        }
    }

    @Test func bool() throws {
        #expect(FDB.Tuple(false).packed == [0x26])
        #expect(FDB.Tuple(true).packed == [0x27])
        #expect(try FDB.Tuple(packed: [0x27]).unpack(as: Bool.self))
    }

    @Test func uuid() throws {
        let raw: uuid_t = (136, 167, 235, 150, 108, 115, 69, 118, 164, 45, 145, 99, 222, 237, 56, 59)
        let uuid = UUID(uuid: raw)
        let packed = FDB.Tuple(uuid).packed
        #expect(packed == [0x30] + withUnsafeBytes(of: raw) { Bytes($0) })
        #expect(try FDB.Tuple(packed: packed).unpack(as: UUID.self) == uuid)
    }

    @Test(arguments: [
        (FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 196), [50, 0, 0, 0, 0, 0, 0, 0, 42, 0, 196]),
        (FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 196, userVersion: 0), [51, 0, 0, 0, 0, 0, 0, 0, 42, 0, 196, 0, 0]),
        (FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 196, userVersion: 24), [51, 0, 0, 0, 0, 0, 0, 0, 42, 0, 196, 0, 24]),
        (FDB.Versionstamp(), [50, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
        (FDB.Versionstamp(userVersion: 0), [51, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0]),
        (FDB.Versionstamp(userVersion: 24), [51, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 24]),
    ] as [(FDB.Versionstamp, Bytes)])
    func versionstamp(value: FDB.Versionstamp, expected: Bytes) throws {
        #expect(FDB.Tuple(value).packed == expected)
        #expect(try FDB.Tuple(packed: expected).unpack(as: FDB.Versionstamp.self) == value)
    }

    @Test(arguments: [
        (FDB.Tuple(FDB.Versionstamp()), 1),
        (FDB.Tuple(FDB.Versionstamp(userVersion: 0)), 1),
        (FDB.Tuple("foo", FDB.Versionstamp()), 6),
        (FDB.Tuple("foo", FDB.Versionstamp(userVersion: 0)), 6),
        (FDB.Tuple("foo", FDB.Versionstamp(transactionCommitVersion: 12, batchNumber: 0), FDB.Versionstamp()), 17),
        (FDB.Tuple("foo", FDB.Versionstamp(transactionCommitVersion: 0, batchNumber: 12), FDB.Versionstamp()), 17),
        (FDB.Tuple("foo", FDB.Tuple(FDB.Versionstamp())), 7),
        (FDB.Tuple("foo", FDB.Tuple("bar", FDB.Versionstamp())), 12),
        (FDB.Tuple("foo", FDB.Tuple(FDB.Null(), FDB.Versionstamp())), 9),
        (try! FDB.Tuple(packed: FDB.Tuple("foo", FDB.Tuple("bar", FDB.Versionstamp())).packed), 12),
    ] as [(FDB.Tuple, Int)])
    func incompleteVersionstampOffset(tuple: FDB.Tuple, offset: Int) throws {
        #expect(try tuple.incompleteVersionstampOffset() == offset)
        #expect(Array(tuple.packed[offset ..< offset + 10]) == Bytes(repeating: 0xFF, count: 10))
        let subspace = FDB.Subspace("prefix")
        #expect(try subspace.subspace(tuple).incompleteVersionstampOffset() == offset + subspace.prefix.count)
    }

    @Test func noIncompleteVersionstamp() throws {
        #expect(try FDB.Tuple().incompleteVersionstampOffset() == nil)
        #expect(try FDB.Tuple(42, "foo", FDB.Versionstamp(transactionCommitVersion: 42, batchNumber: 0)).incompleteVersionstampOffset() == nil)
        #expect(throws: FDB.Error.multipleIncompleteVersionstamps) {
            try FDB.Tuple(FDB.Versionstamp(), FDB.Tuple(FDB.Versionstamp())).incompleteVersionstampOffset()
        }
    }

    @Test func ordering() {
        let sorted = [
            FDB.Tuple(FDB.Null()), FDB.Tuple(Bytes([1])), FDB.Tuple("a"), FDB.Tuple(FDB.Tuple()),
            FDB.Tuple(Int64.min), FDB.Tuple(-1), FDB.Tuple(0), FDB.Tuple(1), FDB.Tuple(UInt64.max),
            FDB.Tuple(Float(-1)), FDB.Tuple(Float(1)), FDB.Tuple(-1.0), FDB.Tuple(1.0), FDB.Tuple(false), FDB.Tuple(true),
        ]
        #expect(sorted.shuffled().sorted() == sorted)
    }

    @Test func subspace() throws {
        let subspace = FDB.Subspace("app", 1)
        let key = subspace["users", 42]
        #expect(key.prefix == FDB.Tuple("app", 1, "users", 42).packed)
        #expect(subspace.contains(key))
        #expect(try subspace.unpack(key).unpack(as: String.self, Int.self) == ("users", 42))
        #expect(subspace.range.begin == subspace.prefix + [0x00])
        #expect(subspace.range.end == subspace.prefix + [0xFF])
        #expect(throws: FDB.Error.unpackInvalidInput) { try subspace.unpack(FDB.Tuple("other")) }
    }

    @Test func keyRangePrefix() {
        #expect(FDB.KeyRange(prefix: Bytes([1, 2, 0xFF])) == FDB.KeyRange(begin: Bytes([1, 2, 0xFF]), end: Bytes([1, 3])))
        #expect(FDB.KeyRange(prefix: "ab").end == Bytes("ac".utf8))
    }

    @Test func printable() {
        #expect(Bytes("abc".utf8).printable == "abc")
        #expect(([0x00, 0x41, 0x5C, 0x7F, 0x80, 0xFF] as Bytes).printable == "\\x00A\\x5C\\x7F\\x80\\xFF")
    }
}
