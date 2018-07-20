extension Array: TuplePackable where Element == Byte {
    public func pack() -> Bytes {
        var result = Bytes()
        result.append(PREFIX_BYTE_STRING)
        self.forEach {
            if $0 == NULL {
                result.append(contentsOf: NULL_ESCAPE_SEQUENCE)
            } else {
                result.append($0)
            }
        }
        result.append(NULL)
        return result
    }
}
