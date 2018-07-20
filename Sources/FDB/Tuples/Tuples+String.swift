extension String: TuplePackable {
    public func pack() -> Bytes {
        var result = Bytes()
        result.append(PREFIX_UTF_STRING)
        Bytes(self.utf8).forEach {
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
