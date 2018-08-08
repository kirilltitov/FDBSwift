extension String: TuplePackable {
    public func pack() -> Bytes {
        let bytes = Bytes(self.utf8)
        var result = Bytes()
        result.append(PREFIX_UTF_STRING)
        bytes.forEach {
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
