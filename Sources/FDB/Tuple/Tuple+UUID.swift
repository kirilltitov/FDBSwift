import Foundation

extension UUID: FDBTuplePackable {
    public func getPackedFDBTupleValue() -> Bytes {
        var result: Bytes = [FDB.Tuple.Prefix.UUID]

        result.append(contentsOf: getBytes(self.uuid))

        return result
    }
}
