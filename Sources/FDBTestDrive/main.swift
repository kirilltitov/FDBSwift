import FDB
import Foundation

extension String {
    var bytes: Bytes {
        return Bytes(self.utf8)
    }
}

extension Array where Element == Byte {
    func cast<R>() -> R {
        precondition(
            MemoryLayout<R>.size == self.count,
            "Memory layout size for result type '\(R.self)' (\(MemoryLayout<R>.size) bytes) does not match with given byte array length (\(self.count) bytes)"
        )
        return self.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: R.self).pointee
        }
    }
    
    var length: Int32 {
        return Int32(self.count)
    }
}

let NULL: Byte                 = 0x00
let PREFIX_BYTE_STRING: Byte   = 0x01
let PREFIX_UTF_STRING: Byte    = 0x02
let PREFIX_NESTED_TUPLE: Byte  = 0x05
let PREFIX_INT_ZERO_CODE: Byte = 0x14
let PREFIX_POS_INT_END: Byte   = 0x1d
let PREFIX_NEG_INT_START: Byte = 0x0b

let NULL_ESCAPE_SEQUENCE: Bytes = [0x00, 0xFF]

/**
    elif code == NESTED_CODE:
        ret = []
        end_pos = pos + 1
        while end_pos < len(v):
            if six.indexbytes(v, end_pos) == 0x00:
                if end_pos + 1 < len(v) and six.indexbytes(v, end_pos + 1) == 0xff:
                    ret.append(None)
                    end_pos += 2
                else:
                    break
            else:
                val, end_pos = _decode(v, end_pos)
                ret.append(val)
        return tuple(ret), end_pos + 1
    else:
        raise ValueError("Unknown data type in DB: " + repr(v))
 */

let sizeLimits = Array<Int>(0...7).map { (1 << ($0 * 8)) - 1 }

@inlinable func findTerminator(input: Bytes, pos: Int) -> Int {
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
    @inlinable func replaceEscapes() -> Bytes {
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

func unpack(_ input: Bytes) -> Tuple {
    var result: [TuplePackable?] = []
    var pos = 0
    let length = input.count
    while pos < length {
        let slice = Bytes(input[pos...])
        let res = _unpack(slice)
        pos += res.1
        result.append(res.0)
    }
    return Tuple(result)
}

func _unpack(_ input: Bytes, _ pos: Int = 0) -> (TuplePackable?, Int) {
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
        let begin = pos + 1
        let end = findTerminator(input: input, pos: _pos)
        let bytes = input[begin..<end].replaceEscapes()
        return (String(bytes: bytes, encoding: .utf8), end + 1)
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

var expected = Bytes()
//expected = Tuple(Bytes([0,1,2]), 322, -322, nil, "foo", Tuple("bar", 1337, "baz")).pack()
//print(expected)
//expected.append(0x02)
//expected.append(contentsOf: "F".bytes)
//expected.append(0xC3)
//expected.append(0x94)
//expected.append(contentsOf: "O".bytes)
//expected.append(0x00)
//expected.append(0xFF)
//expected.append(contentsOf: "bar".bytes)
//expected.append(0x00)
// pack( (“foo\x00bar”, None, ()) ) == b'\x05\x01foo\x00\xffbar\x00\x00\xff\x05\x00\x00'

let etalonTuple = Tuple(Bytes([0,1,2]), 322, "foo\u{00}bar", -322, nil, "foo", Tuple("bar", 1337, "baz"))
let packed = etalonTuple.pack()
print(packed)
let unpackedTuple = unpack(packed)
//dump(unpackedTuple)
let packedAgain = unpackedTuple.pack()
print(packedAgain)

dump(packed == packedAgain)

//let unpacked: Tuple = unpack(expected)

//dump(unpacked)
