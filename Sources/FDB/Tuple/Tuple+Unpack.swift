import Foundation

internal func findTerminator(input: Bytes, pos: Int) -> Int {
    let length = input.count
    var _pos = pos
    while true {
        guard let __pos = input[_pos...].firstIndex(of: 0x00) else {
            return length
        }
        _pos = __pos
        if _pos + 1 == length || input[_pos + 1] != 0xff {
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
        var i = 0
        while true {
            i += 1
            if self[pos] == 0x00 && pos < lastIndex && self[pos + 1] == 0xff {
                result.append(0x00)
                pos += 2
                continue
            }
            result.append(self[pos])
            if pos == lastIndex {
                break
            }
            pos += 1
        }
        return result
    }
}

extension Tuple {
    public init(from bytes: Bytes) {
        var result: [TuplePackable?] = []
        var pos = 0
        let length = bytes.count
        while pos < length {
            let slice = Bytes(bytes[pos...])
            let res = Tuple._unpack(slice)
            pos += res.1
            result.append(res.0)
        }
        self.init(result)
    }

    internal static func _unpack(_ input: Bytes, _ pos: Int = 0) -> (TuplePackable?, Int) {
        guard input.count > 0 else {
            fatalError("Input is empty")
        }
        let code = input[pos]
        if code == NULL {
            return (nil, pos + 1)
        } else if code == PREFIX_BYTE_STRING {
            let end = findTerminator(input: input, pos: pos + 1)
            return (input[(pos + 1)..<end].replaceEscapes(), end + 1)
        } else if code == PREFIX_UTF_STRING {
            let _pos = pos + 1
            let end = findTerminator(input: input, pos: _pos)
            let bytes = input[(pos + 1)..<end].replaceEscapes()
            return (
                String(bytes: bytes, encoding: .utf8),
                end + 1
            )
        } else if code >= PREFIX_INT_ZERO_CODE && code < PREFIX_POS_INT_END {
            let n = Int(code) - 20
            let begin = pos + 1
            let end = begin + n
            return ((Array<Byte>(repeating: 0x00, count: 8 - n) + input[begin..<end]).reversed().cast() as Int, end)
        } else if code > PREFIX_NEG_INT_START && code < PREFIX_INT_ZERO_CODE {
            let n = 20 - Int(code)
            let begin = pos + 1
            let end = pos + 1 + n
            guard sizeLimits.count >= n else {
                fatalError("Int too large to unpack")
            }
            return (((Array<Byte>(repeating: 0x00, count: 8 - n) + input[begin..<end]).reversed().cast() as Int) - sizeLimits[n], end)
        } else if code == PREFIX_NESTED_TUPLE {
            var result: [TuplePackable?] = []
            var end = pos + 1
            while end < input.count {
                if input[end] == 0x00 {
                    if end + 1 < input.count && input[end + 1] == 0xff {
                        result.append(nil)
                        end += 2
                    } else {
                        break
                    }
                } else {
                    let _res = _unpack(input, end)
                    result.append(_res.0)
                    end = _res.1
                }
            }
            return (Tuple(result), end + 1)
        }
        fatalError("Unknown code '\(code)'")
    }
}
