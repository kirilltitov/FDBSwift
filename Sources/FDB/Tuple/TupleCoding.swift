#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Type codes of the [tuple layer](https://github.com/apple/foundationdb/blob/main/design/tuple.md)
enum TupleCode {
    static let null: UInt8 = 0x00
    static let bytes: UInt8 = 0x01
    static let string: UInt8 = 0x02
    static let nested: UInt8 = 0x05
    static let negativeInt8: UInt8 = 0x0C // 8-byte negative integer
    static let intZero: UInt8 = 0x14
    static let positiveInt8: UInt8 = 0x1C // 8-byte positive integer
    static let float: UInt8 = 0x20
    static let double: UInt8 = 0x21
    static let `false`: UInt8 = 0x26
    static let `true`: UInt8 = 0x27
    static let uuid: UInt8 = 0x30
    static let versionstamp80: UInt8 = 0x32
    static let versionstamp96: UInt8 = 0x33
}

extension FDB {
    /// Encodes tuple elements into a single buffer, see ``FDB.TuplePackable``
    public struct TupleEncoder: Sendable {
        var bytes: Bytes = []
        var versionstampOffset: Int?
        var versionstampCount = 0

        init() {}

        public mutating func appendNull() {
            self.bytes.append(TupleCode.null)
        }

        public mutating func appendBytes(_ value: some Collection<UInt8>) {
            self.bytes.append(TupleCode.bytes)
            self.appendEscaped(value)
        }

        public mutating func appendString(_ value: String) {
            self.bytes.append(TupleCode.string)
            self.appendEscaped(value.utf8)
        }

        public mutating func appendBool(_ value: Bool) {
            self.bytes.append(value ? TupleCode.true : TupleCode.false)
        }

        public mutating func appendInt(_ value: Int64) {
            if value >= 0 {
                self.appendUInt(UInt64(value))
                return
            }
            // Negative n-byte integers are stored as one's complement of their magnitude
            let magnitude = value.magnitude
            let length = Self.byteLength(magnitude)
            self.bytes.append(TupleCode.intZero - UInt8(length))
            self.appendBigEndian(~magnitude, length: length)
        }

        public mutating func appendUInt(_ value: UInt64) {
            let length = Self.byteLength(value)
            self.bytes.append(TupleCode.intZero + UInt8(length))
            self.appendBigEndian(value, length: length)
        }

        public mutating func appendFloat(_ value: Float) {
            self.bytes.append(TupleCode.float)
            let bits = value.bitPattern
            // Negative numbers have all bits flipped, positive ones only the sign bit, so that byte order matches
            // numeric order
            self.appendBigEndian(UInt64(bits & 0x8000_0000 != 0 ? ~bits : bits ^ 0x8000_0000), length: 4)
        }

        public mutating func appendDouble(_ value: Double) {
            self.bytes.append(TupleCode.double)
            let bits = value.bitPattern
            self.appendBigEndian(bits & (1 << 63) != 0 ? ~bits : bits ^ (1 << 63), length: 8)
        }

        public mutating func appendUUID(_ value: UUID) {
            self.bytes.append(TupleCode.uuid)
            withUnsafeBytes(of: value.uuid) { self.bytes.append(contentsOf: $0) }
        }

        public mutating func appendVersionstamp(_ value: FDB.Versionstamp) {
            self.bytes.append(value.userVersion == nil ? TupleCode.versionstamp80 : TupleCode.versionstamp96)
            if !value.isComplete {
                self.versionstampCount += 1
                if self.versionstampOffset == nil {
                    self.versionstampOffset = self.bytes.count
                }
            }
            self.appendBigEndian(value.transactionCommitVersion, length: 8)
            self.appendBigEndian(UInt64(value.batchNumber), length: 2)
            if let userVersion = value.userVersion {
                self.appendBigEndian(UInt64(userVersion), length: 2)
            }
        }

        /// Appends a nested tuple
        public mutating func appendNested(_ tuple: FDB.Tuple) {
            self.bytes.append(TupleCode.nested)
            // Packed tuple can be copied element by element as is, except for top-level nulls which
            // must be escaped within a nested tuple
            var decoder = TupleDecoder(tuple.packed)
            var ignored = VersionstampInfo()
            while !decoder.isAtEnd {
                let start = decoder.position
                // Packed tuple is always valid, as it was either encoded by us or validated on decoding
                try! decoder.skipElement(&ignored)
                if tuple.packed[start] == TupleCode.null {
                    self.bytes.append(contentsOf: [TupleCode.null, 0xFF])
                    continue
                }
                if let offset = tuple.versionstampOffset, (start ..< decoder.position).contains(offset) {
                    if self.versionstampOffset == nil {
                        self.versionstampOffset = self.bytes.count + (offset - start)
                    }
                }
                self.bytes.append(contentsOf: tuple.packed[start ..< decoder.position])
            }
            self.versionstampCount += tuple.versionstampCount
            self.bytes.append(TupleCode.null)
        }

        private mutating func appendEscaped(_ value: some Collection<UInt8>) {
            self.bytes.reserveCapacity(self.bytes.count + value.count + 1)
            for byte in value {
                self.bytes.append(byte)
                if byte == 0x00 {
                    self.bytes.append(0xFF)
                }
            }
            self.bytes.append(TupleCode.null)
        }

        private mutating func appendBigEndian(_ value: UInt64, length: Int) {
            for shift in stride(from: (length - 1) * 8, through: 0, by: -8) {
                self.bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
        }

        private static func byteLength(_ value: UInt64) -> Int {
            (UInt64.bitWidth - value.leadingZeroBitCount + 7) / 8
        }
    }

    /// Information about incomplete versionstamps found while scanning a packed tuple
    struct VersionstampInfo {
        var firstOffset: Int?
        var count = 0
    }

    /// Decodes tuple elements one by one.
    ///
    /// All positions are absolute indices in `bytes`.
    struct TupleDecoder {
        /// Maximum nesting depth of tuples: deeper input is rejected instead of overflowing the stack
        static let maxDepth = 64

        let bytes: Bytes
        private(set) var position: Int

        init(_ bytes: Bytes) {
            self.bytes = bytes
            self.position = 0
        }

        var isAtEnd: Bool {
            self.position >= self.bytes.count
        }

        mutating func next<T: FDB.TupleUnpackable>(_ type: T.Type) throws(FDB.Error) -> T {
            guard !self.isAtEnd else {
                throw .unpackTypeMismatch
            }
            return try T(tupleElement: self.nextElement())
        }

        /// Validates the next element and moves past it without materializing it.
        ///
        /// Cost is linear in the size of the element, including nested tuples.
        mutating func skipElement(_ versionstamps: inout VersionstampInfo, depth: Int = 0) throws(FDB.Error) {
            let code = try self.readByte()
            switch code {
            case TupleCode.null, TupleCode.false, TupleCode.true:
                return
            case TupleCode.bytes:
                try self.skipEscaped(validateUTF8: false)
            case TupleCode.string:
                try self.skipEscaped(validateUTF8: true)
            case TupleCode.nested:
                guard depth < Self.maxDepth else {
                    throw .unpackTooDeep
                }
                while true {
                    guard !self.isAtEnd else {
                        throw .unpackInvalidInput
                    }
                    if self.bytes[self.position] == TupleCode.null {
                        if self.position + 1 < self.bytes.count && self.bytes[self.position + 1] == 0xFF {
                            self.position += 2
                            continue
                        }
                        self.position += 1
                        return
                    }
                    try self.skipElement(&versionstamps, depth: depth + 1)
                }
            case TupleCode.negativeInt8 ..< TupleCode.intZero:
                _ = try self.read(count: Int(TupleCode.intZero - code))
            case TupleCode.intZero ... TupleCode.positiveInt8:
                _ = try self.read(count: Int(code - TupleCode.intZero))
            case TupleCode.float:
                _ = try self.read(count: 4)
            case TupleCode.double:
                _ = try self.read(count: 8)
            case TupleCode.uuid:
                _ = try self.read(count: 16)
            case TupleCode.versionstamp80, TupleCode.versionstamp96:
                let offset = self.position
                let raw = try self.read(count: code == TupleCode.versionstamp96 ? 12 : 10)
                if raw.prefix(10).allSatisfy({ $0 == 0xFF }) {
                    versionstamps.count += 1
                    if versionstamps.firstOffset == nil {
                        versionstamps.firstOffset = offset
                    }
                }
            default:
                throw .unpackUnknownCode
            }
        }

        /// Decodes the next element
        mutating func nextElement() throws(FDB.Error) -> FDB.TupleElement {
            let code = try self.readByte()
            switch code {
            case TupleCode.null:
                return .null
            case TupleCode.bytes:
                return .bytes(try self.readEscaped())
            case TupleCode.string:
                guard let string = String(validating: try self.readEscaped(), as: UTF8.self) else {
                    throw .unpackInvalidString
                }
                return .string(string)
            case TupleCode.nested:
                return .tuple(try self.readNested())
            case TupleCode.negativeInt8 ..< TupleCode.intZero:
                let length = Int(TupleCode.intZero - code)
                let magnitude = ~(try self.readBigEndian(length: length)) & Self.mask(length: length)
                guard magnitude <= UInt64(Int64.max) + 1 else {
                    throw .unpackTooLargeInt
                }
                return .int(magnitude == UInt64(Int64.max) + 1 ? .min : -Int64(magnitude))
            case TupleCode.intZero ... TupleCode.positiveInt8:
                let value = try self.readBigEndian(length: Int(code - TupleCode.intZero))
                return value <= UInt64(Int64.max) ? .int(Int64(value)) : .uint(value)
            case TupleCode.float:
                let bits = UInt32(try self.readBigEndian(length: 4))
                return .float(Float(bitPattern: bits & 0x8000_0000 != 0 ? bits ^ 0x8000_0000 : ~bits))
            case TupleCode.double:
                let bits = try self.readBigEndian(length: 8)
                return .double(Double(bitPattern: bits & (1 << 63) != 0 ? bits ^ (1 << 63) : ~bits))
            case TupleCode.false:
                return .bool(false)
            case TupleCode.true:
                return .bool(true)
            case TupleCode.uuid:
                let bytes = try self.read(count: 16)
                let uuid = bytes.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) }
                return .uuid(UUID(uuid: uuid))
            case TupleCode.versionstamp80, TupleCode.versionstamp96:
                let version = try self.readBigEndian(length: 8)
                let batch = UInt16(try self.readBigEndian(length: 2))
                let user = code == TupleCode.versionstamp96 ? UInt16(try self.readBigEndian(length: 2)) : nil
                return .versionstamp(.init(transactionCommitVersion: version, batchNumber: batch, userVersion: user))
            default:
                throw .unpackUnknownCode
            }
        }

        /// Reads a nested tuple: its elements are copied as is (they're encoded identically at the top level),
        /// except for escaped nulls
        private mutating func readNested() throws(FDB.Error) -> FDB.Tuple {
            var packed = Bytes()
            var versionstamps = VersionstampInfo()
            while true {
                guard !self.isAtEnd else {
                    // Nested tuple must be terminated
                    throw .unpackInvalidInput
                }
                if self.bytes[self.position] == TupleCode.null {
                    if self.position + 1 < self.bytes.count && self.bytes[self.position + 1] == 0xFF {
                        packed.append(TupleCode.null)
                        self.position += 2
                        continue
                    }
                    self.position += 1
                    return FDB.Tuple(validatedPacked: packed)
                }
                let start = self.position
                try self.skipElement(&versionstamps, depth: 1)
                packed.append(contentsOf: self.bytes[start ..< self.position])
            }
        }

        private mutating func readByte() throws(FDB.Error) -> UInt8 {
            guard !self.isAtEnd else {
                throw .unpackInvalidInput
            }
            defer { self.position += 1 }
            return self.bytes[self.position]
        }

        private mutating func read(count: Int) throws(FDB.Error) -> ArraySlice<UInt8> {
            guard self.position + count <= self.bytes.count else {
                throw .unpackInvalidInput
            }
            defer { self.position += count }
            return self.bytes[self.position ..< self.position + count]
        }

        private mutating func readBigEndian(length: Int) throws(FDB.Error) -> UInt64 {
            var result: UInt64 = 0
            for byte in try self.read(count: length) {
                result = result << 8 | UInt64(byte)
            }
            return result
        }

        /// Reads a null-terminated escaped byte string
        private mutating func readEscaped() throws(FDB.Error) -> Bytes {
            var result = Bytes()
            while true {
                let byte = try self.readByte()
                if byte != 0x00 {
                    result.append(byte)
                    continue
                }
                if self.position < self.bytes.count && self.bytes[self.position] == 0xFF {
                    result.append(0x00)
                    self.position += 1
                    continue
                }
                return result
            }
        }

        private mutating func skipEscaped(validateUTF8: Bool) throws(FDB.Error) {
            if validateUTF8 {
                guard String(validating: try self.readEscaped(), as: UTF8.self) != nil else {
                    throw .unpackInvalidString
                }
                return
            }
            while true {
                if try self.readByte() != 0x00 {
                    continue
                }
                if self.position < self.bytes.count && self.bytes[self.position] == 0xFF {
                    self.position += 1
                    continue
                }
                return
            }
        }

        private static func mask(length: Int) -> UInt64 {
            length >= 8 ? .max : (1 << UInt64(length * 8)) - 1
        }
    }
}
