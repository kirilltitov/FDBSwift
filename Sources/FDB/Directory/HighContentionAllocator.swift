extension FDB {
    /// Allocates short unique prefixes for new directories, with few conflicts between concurrent allocations.
    ///
    /// Same algorithm and storage format as in other FoundationDB bindings: candidates are picked at random within a
    /// window of integers, which grows as more prefixes are allocated.
    struct HighContentionAllocator: Sendable {
        let counters: Subspace
        let recent: Subspace

        init(_ subspace: Subspace) {
            self.counters = subspace[0]
            self.recent = subspace[1]
        }

        /// Returns a packed tuple with an integer which has never been (and never will be) returned
        /// for the same subspace, nearly as short as possible
        func allocate(in tr: borrowing Transaction) async throws(FDB.Error) -> Bytes {
            while true {
                var start = try await self.latestCounter(in: tr) ?? 0
                var windowAdvanced = false
                var window: Int64

                while true {
                    if windowAdvanced {
                        tr.clear(range: KeyRange(begin: self.counters.prefix, end: self.counters[start]))
                        try tr.setOption(.nextWriteNoWriteConflictRange)
                        tr.clear(range: KeyRange(begin: self.recent.prefix, end: self.recent[start]))
                    }

                    // Increment the allocation count for the current window
                    // (and issue the read right away, without suspending in between)
                    tr.atomic(.add, key: self.counters[start], value: Self.encode(1))
                    let countFuture = tr.get(key: self.counters[start], snapshot: true)
                    let count = try await countFuture.value.map(Self.decode) ?? 0

                    window = Self.windowSize(start: start)
                    if count * 2 < window {
                        break
                    }
                    start += window
                    windowAdvanced = true
                }

                while true {
                    // As of the snapshot being read from, the window is less than half full,
                    // so this is expected to take about two tries
                    let candidate = Int64.random(in: start ..< start + window)

                    let latest = try await self.latestCounter(in: tr)
                    // The read is issued before the write without suspending in between, so even if the transaction
                    // is used concurrently, allocations in it can't both see the candidate as free
                    let candidateFuture = tr.get(key: self.recent[candidate])
                    try tr.setOption(.nextWriteNoWriteConflictRange)
                    tr.set(key: self.recent[candidate], value: [])
                    let candidateValue = try await candidateFuture.value

                    if let latest, latest > start {
                        // The window has been advanced concurrently, start over
                        break
                    }
                    if candidateValue == nil {
                        try tr.addWriteConflict(key: self.recent[candidate])
                        return Tuple(candidate).packed
                    }
                }
            }
        }

        private func latestCounter(in tr: borrowing Transaction) async throws(FDB.Error) -> Int64? {
            let records = try await tr.getAll(self.counters.range, limit: 1, snapshot: true, reverse: true)
            guard let key = records.first?.key else {
                return nil
            }
            guard case let .int(value) = try self.counters.unpack(key).elements.first else {
                throw .unpackTypeMismatch
            }
            return value
        }

        /// Larger windows are better under high contention, smaller ones keep the prefixes short.
        /// About half a window of recent allocations is stored, so it shouldn't get too large either.
        private static func windowSize(start: Int64) -> Int64 {
            if start < 255 {
                return 64
            }
            if start < 65535 {
                return 1024
            }
            return 8192
        }

        private static func encode(_ value: Int64) -> Bytes {
            withUnsafeBytes(of: value.littleEndian) { Bytes($0) }
        }

        private static func decode(_ bytes: Bytes) -> Int64 {
            var value: Int64 = 0
            for (index, byte) in bytes.prefix(8).enumerated() {
                value |= Int64(byte) << (index * 8)
            }
            return value
        }
    }
}
