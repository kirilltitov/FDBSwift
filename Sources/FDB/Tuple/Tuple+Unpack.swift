import Foundation
import LGNLog
import Helpers

@inlinable
internal func findTerminator(input: Bytes, pos: Int) -> Int {
    let length = input.count
    var _pos = pos
    while true {
        guard let __pos = input[_pos...].firstIndex(of: 0x00) else {
            return length
        }
        _pos = __pos
        if _pos + 1 == length || input[_pos + 1] != 0xFF {
            return _pos
        }
        _pos += 2
    }
}

extension ArraySlice where Element == Byte {
    internal func replaceEscapes() -> Bytes {
        if self.count == 0 {
            return []
        }
        var result = Bytes()
        var pos = self.startIndex
        let lastIndex = self.endIndex - 1
        while true {
            if pos > lastIndex {
                break
            }
            if self[pos] == 0x00 && pos < lastIndex && self[pos + 1] == 0xFF {
                result.append(0x00)
                pos += 2
                continue
            }
            result.append(self[pos])
            pos += 1
        }
        return result
    }
}

extension FDB.Tuple {
    public init(from bytes: Bytes) throws {
        var result: [FDBTuplePackable] = []
        var pos = 0
        let length = bytes.count
        while pos < length {
            let slice = Bytes(bytes[pos...])
            let res = try FDB.Tuple._unpack(slice)
            pos += res.1
            result.append(res.0)
        }
        self.init(result)
    }

    internal static func _unpack(_ input: Bytes, _ pos: Int = 0) throws -> (FDBTuplePackable, Int) {
        func sanityCheck(begin: Int, end: Int) throws {
            guard begin >= input.startIndex else {
                Logger.current.error("Invalid begin boundary \(begin) (actual: \(input.startIndex)) while parsing \(input)")
                throw FDB.Error.unpackInvalidBoundaries
            }
            guard end <= input.endIndex else {
                Logger.current.error("Invalid end boundary \(end) (actual: \(input.endIndex)) while parsing \(input)")
                throw FDB.Error.unpackInvalidBoundaries
            }
        }

        guard input.count > 0 else {
            throw FDB.Error.unpackEmptyInput
        }

        let code = input[pos]
        if code == NULL {
            return (FDB.Null(), pos + 1)
        } else if code == FDB.Tuple.Prefix.BYTE_STRING {
            let end = findTerminator(input: input, pos: pos + 1)
            try sanityCheck(begin: pos + 1, end: end)
            return (input[(pos + 1) ..< end].replaceEscapes(), end + 1)
        } else if code == FDB.Tuple.Prefix.UTF_STRING {
            let _pos = pos + 1
            let end = findTerminator(input: input, pos: _pos)
            try sanityCheck(begin: pos + 1, end: end)
            let bytes = input[(pos + 1) ..< end].replaceEscapes()
            guard let string = String(bytes: bytes, encoding: .utf8) else {
                Logger.current.error("Could not convert bytes \(bytes) to string (ascii form: '\(String(bytes: bytes, encoding: .ascii)!)')")
                throw FDB.Error.unpackInvalidString
            }
            return (string, end + 1)
        } else if code >= FDB.Tuple.Prefix.INT_ZERO_CODE && code < FDB.Tuple.Prefix.POS_INT_END {
            let n = Int(code) - 20
            let begin = pos + 1
            let end = begin + n
            try sanityCheck(begin: begin, end: end)
            return try (
                (Array<Byte>(repeating: 0x00, count: 8 - n) + input[begin ..< end]).reversed().cast(error: FDB.Error.unexpectedError) as Int,
                end
            )
        } else if code > FDB.Tuple.Prefix.NEG_INT_START && code < FDB.Tuple.Prefix.INT_ZERO_CODE {
            let n = 20 - Int(code)
            let begin = pos + 1
            let end = pos + 1 + n
            guard n < sizeLimits.endIndex else {
                throw FDB.Error.unpackTooLargeInt
            }
            try sanityCheck(begin: begin, end: end)
            return try (
                (
                    (
                        Array<Byte>(
                            repeating: 0x00,
                            count: 8 - n
                        )
                            + input[begin ..< end]
                    ).reversed().cast(error: FDB.Error.unexpectedError) as Int
                ) - sizeLimits[n],
                end
            )
        } else if code == FDB.Tuple.Prefix.NESTED_TUPLE {
            var result: [FDBTuplePackable] = []
            var end = pos + 1
            while end < input.count {
                if input[end] == 0x00 {
                    if end + 1 < input.count && input[end + 1] == 0xFF {
                        result.append(FDB.Null())
                        end += 2
                    } else {
                        break
                    }
                } else {
                    let _res = try FDB.Tuple._unpack(input, end)
                    result.append(_res.0)
                    end = _res.1
                }
            }
            return (FDB.Tuple(result), end + 1)
        } else if code == FDB.Tuple.Prefix.FLOAT {
            let end = pos + 1 + MemoryLayout<Float32>.size
            try sanityCheck(begin: pos + 1, end: end)
            var bytes = Bytes(input[(pos + 1) ..< end])
            transformFloatingPoint(bytes: &bytes, start: 0, encode: false)
            return try (
                Float32(bitPattern: (bytes.cast(error: FDB.Error.unexpectedError) as UInt32).bigEndian),
                end
            )
        } else if code == FDB.Tuple.Prefix.DOUBLE {
            let end = pos + 1 + MemoryLayout<Double>.size
            try sanityCheck(begin: pos + 1, end: end)
            var bytes = Bytes(input[(pos + 1) ..< end])
            transformFloatingPoint(bytes: &bytes, start: 0, encode: false)
            return try (
                Double(bitPattern: (bytes.cast(error: FDB.Error.unexpectedError) as UInt64).bigEndian),
                end
            )
        } else if code == FDB.Tuple.Prefix.BOOL_TRUE || code == FDB.Tuple.Prefix.BOOL_FALSE {
            return (
                code == FDB.Tuple.Prefix.BOOL_TRUE,
                pos + 1
            )
        } else if code == FDB.Tuple.Prefix.UUID {
            let end = pos + 1 + MemoryLayout<uuid_t>.size
            try sanityCheck(begin: pos + 1, end: end)
            return try (
                UUID(uuid: Bytes(input[(pos + 1) ..< end]).cast(error: FDB.Error.unexpectedError)),
                end
            )
        } else if code == FDB.Tuple.Prefix.VERSIONSTAMP_80BIT || code == FDB.Tuple.Prefix.VERSIONSTAMP_96BIT {
            var pos = pos
            var end = pos + 1 + MemoryLayout<UInt64>.size
            try sanityCheck(begin: pos + 1, end: end)
            let transactionCommitVersion = try UInt64(bigEndian: Bytes(input[(pos + 1) ..< end]).cast(error: FDB.Error.unexpectedError))
            
            pos = end
            end = pos + MemoryLayout<UInt16>.size
            try sanityCheck(begin: pos, end: end)
            let batchNumber = try UInt16(bigEndian: Bytes(input[pos ..< end]).cast(error: FDB.Error.unexpectedError))
            
            var userData: UInt16? = nil
            if code == FDB.Tuple.Prefix.VERSIONSTAMP_96BIT {
                pos = end
                end = pos + MemoryLayout<UInt16>.size
                try sanityCheck(begin: pos, end: end)
                userData = try UInt16(bigEndian: Bytes(input[pos ..< end]).cast(error: FDB.Error.unexpectedError))
            }
            return (
                FDB.Versionstamp(transactionCommitVersion: transactionCommitVersion, batchNumber: batchNumber, userData: userData),
                end
            )
        }

        Logger.current.error("Unknown tuple code '\(code)' while parsing \(input) (\(input.string))")
        throw FDB.Error.unpackUnknownCode
    }
}
