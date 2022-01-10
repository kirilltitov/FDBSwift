extension Collection {
    internal subscript(from i: Int) -> SubSequence {
        let _from = self.index(self.endIndex, offsetBy: i)
        let _to = self.endIndex

        return self[_from ..< _to]
    }
}

internal func bisect(list: [Int], item: Int) -> Int {
    var count = 0

    for i in list {
        if i >= item {
            break
        }
        count += 1
    }

    return count
}

internal let sizeLimits = Array<Int>(0 ... 7).map { (1 << ($0 * 8)) - 1 }

extension Int: FDBTuplePackable {
    public func getPackedFDBTupleValue() -> Bytes {
        if self == 0 {
            return [FDB.Tuple.Prefix.INT_ZERO_CODE]
        }

        var result = Bytes()

        if self > 0 {
            let n = bisect(list: sizeLimits, item: self)
            result.append(FDB.Tuple.Prefix.INT_ZERO_CODE + UInt8(n))
            result.append(contentsOf: getBytes(self.bigEndian)[from: -n])
        } else {
            let n = bisect(list: sizeLimits, item: -self)
            result.append(FDB.Tuple.Prefix.INT_ZERO_CODE - UInt8(n))
            let maxv = sizeLimits[n]
            let bytes = getBytes((maxv + self).bigEndian)
            result.append(contentsOf: bytes[from: -n])
        }

        return result
    }
}
