import CFDB

extension FDB {
    /// A batch of key-value pairs returned by a range read, pointing directly into the memory of the
    /// FoundationDB client.
    ///
    /// The batch is only lent to the closure of ``FDB/Transaction/forEachBatch(in:limit:mode:snapshot:reverse:_:)``
    /// and can't escape it (it's non-copyable), so the memory it points to is guaranteed to be alive while it's used.
    /// Keys and values are exposed as `Span`s; use ``keyValue(at:)`` or ``copyAll()`` to copy them out.
    public struct KeyValueBatch: ~Copyable {
        /// `FDBKeyValue` array. It's declared with `#pragma pack(4)` in `fdb_c.h`, so elements may be misaligned
        /// for Swift and must be read with unaligned loads.
        private let base: UnsafeRawPointer?

        /// Number of key-value pairs in the batch
        public let count: Int

        /// Whether there are more key-value pairs in the requested range after this batch
        public let hasMore: Bool

        init(_ future: OpaquePointer) throws(FDB.Error) {
            var array: UnsafePointer<FDBKeyValue>?
            var count: Int32 = 0
            var more: fdb_bool_t = 0
            try fdb_future_get_keyvalue_array(future, &array, &count, &more).check()
            self.base = array.map(UnsafeRawPointer.init)
            self.count = Int(count)
            self.hasMore = more != 0
        }

        public var isEmpty: Bool {
            self.count == 0
        }

        private func entry(at index: Int) -> FDBKeyValue {
            precondition(index >= 0 && index < self.count, "Index \(index) is out of bounds (count: \(self.count))")
            return self.base!.loadUnaligned(fromByteOffset: index * MemoryLayout<FDBKeyValue>.stride, as: FDBKeyValue.self)
        }

        /// Calls given closure with the key and the value at given index, without copying them
        public func withKeyValue<R, E: Swift.Error>(
            at index: Int,
            _ body: (_ key: Span<UInt8>, _ value: Span<UInt8>) throws(E) -> R
        ) throws(E) -> R {
            let entry = self.entry(at: index)
            let key = UnsafeBufferPointer(start: entry.key, count: Int(entry.key_length))
            let value = UnsafeBufferPointer(start: entry.value, count: Int(entry.value_length))
            return try body(key.span, value.span)
        }

        /// Calls given closure with each key and value, without copying them
        public func forEach<E: Swift.Error>(_ body: (_ key: Span<UInt8>, _ value: Span<UInt8>) throws(E) -> Void) throws(E) {
            for index in 0 ..< self.count {
                try self.withKeyValue(at: index, body)
            }
        }

        /// Copies the key at given index
        public func key(at index: Int) -> Bytes {
            let entry = self.entry(at: index)
            return Bytes(UnsafeBufferPointer(start: entry.key, count: Int(entry.key_length)))
        }

        /// Copies the key-value pair at given index
        public func keyValue(at index: Int) -> KeyValue {
            let entry = self.entry(at: index)
            return KeyValue(
                key: Bytes(UnsafeBufferPointer(start: entry.key, count: Int(entry.key_length))),
                value: Bytes(UnsafeBufferPointer(start: entry.value, count: Int(entry.value_length)))
            )
        }

        /// Copies all key-value pairs of the batch
        public func copyAll() -> [KeyValue] {
            var result: [KeyValue] = []
            result.reserveCapacity(self.count)
            for index in 0 ..< self.count {
                result.append(self.keyValue(at: index))
            }
            return result
        }
    }
}
