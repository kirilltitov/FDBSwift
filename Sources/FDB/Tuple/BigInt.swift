extension FDB {
    /// An integer of arbitrary size as stored in tuples: a sign and a big-endian magnitude of up to 255 bytes
    /// (i.e. up to 2040 bits, the limit of the tuple encoding).
    ///
    /// The tuple layer supports integers wider than 64 bits (other bindings use big integers for them). This type
    /// stores them losslessly, so such keys can be read, compared and written back. It doesn't do arithmetic:
    /// convert to a fixed-width integer (``init(_:)`` / ``exactly(_:)``) when the value fits.
    public struct BigInt: Hashable, Sendable, CustomStringConvertible {
        /// Maximum length of the magnitude in bytes
        public static let maxMagnitudeLength = 255

        /// Whether the value is negative (zero is never negative)
        public let isNegative: Bool

        /// Big-endian magnitude without leading zero bytes (empty for zero)
        public let magnitude: Bytes

        /// Creates a value from a sign and a big-endian magnitude.
        ///
        /// Returns `nil` if the magnitude is longer than ``maxMagnitudeLength`` bytes (leading zeros aside).
        public init?(isNegative: Bool, magnitude: some Collection<UInt8>) {
            let magnitude = Bytes(magnitude.drop(while: { $0 == 0 }))
            guard magnitude.count <= Self.maxMagnitudeLength else {
                return nil
            }
            self.magnitude = magnitude
            self.isNegative = isNegative && !magnitude.isEmpty
        }

        /// Creates a value from any binary integer (up to 2040 bits)
        public init(_ value: some BinaryInteger) {
            var bytes = Bytes()
            var magnitude = value.magnitude
            while magnitude != 0 {
                bytes.append(UInt8(truncatingIfNeeded: magnitude))
                magnitude >>= 8
            }
            self.init(isNegative: value < 0, magnitude: bytes.reversed())!
        }

        init(magnitude: UInt64, isNegative: Bool) {
            self.init(isNegative: isNegative, magnitude: withUnsafeBytes(of: magnitude.bigEndian) { Bytes($0) })!
        }

        /// Converts to a fixed-width integer, `nil` if the value doesn't fit
        public func exactly<T: FixedWidthInteger>(_ type: T.Type = T.self) -> T? {
            guard self.magnitude.count * 8 <= T.bitWidth + 8 else {
                return nil
            }
            // Accumulate the magnitude in the unsigned counterpart of T, then apply the sign
            var result: T.Magnitude = 0
            for byte in self.magnitude {
                guard result.leadingZeroBitCount >= 8 else {
                    return nil
                }
                result = result << 8 | T.Magnitude(byte)
            }
            if self.isNegative {
                guard T.isSigned else {
                    return nil
                }
                // -|T.min| is representable, so the magnitude may exceed T.max by one
                if result == T.Magnitude(T.max) + 1 {
                    return T.min
                }
                return T(exactly: result).map { 0 - $0 }
            }
            return T(exactly: result)
        }

        /// Decimal representation
        public var description: String {
            if self.magnitude.isEmpty {
                return "0"
            }
            // Repeated division of the big-endian magnitude by 10
            var digits: [UInt8] = []
            var current = self.magnitude
            while !current.isEmpty {
                var remainder = 0
                var next = Bytes()
                next.reserveCapacity(current.count)
                for byte in current {
                    let value = remainder << 8 | Int(byte)
                    let quotient = value / 10
                    remainder = value % 10
                    if !(next.isEmpty && quotient == 0) {
                        next.append(UInt8(quotient))
                    }
                }
                digits.append(UInt8(remainder))
                current = next
            }
            return (self.isNegative ? "-" : "") + String(digits.reversed().map { Character(String($0)) })
        }

        /// Canonical tuple element for this value: ``FDB/TupleElement/int(_:)`` or ``FDB/TupleElement/uint(_:)``
        /// when it fits, ``FDB/TupleElement/bigInt(_:)`` otherwise
        public var tupleElement: TupleElement {
            if let value = self.exactly(Int64.self) {
                return .int(value)
            }
            if let value = self.exactly(UInt64.self) {
                return .uint(value)
            }
            return .bigInt(self)
        }
    }
}

extension FDB.BigInt: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendBigInt(self)
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        switch tupleElement {
        case let .int(value): self.init(value)
        case let .uint(value): self.init(value)
        case let .bigInt(value): self = value
        default: throw .unpackTypeMismatch
        }
    }
}

extension Int128: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendBigInt(FDB.BigInt(self))
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard let value = try FDB.BigInt(tupleElement: tupleElement).exactly(Int128.self) else {
            throw .unpackTooLargeInt
        }
        self = value
    }
}

extension UInt128: FDB.TupleCodable {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendBigInt(FDB.BigInt(self))
    }

    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard let value = try FDB.BigInt(tupleElement: tupleElement).exactly(UInt128.self) else {
            throw .unpackTooLargeInt
        }
        self = value
    }
}
