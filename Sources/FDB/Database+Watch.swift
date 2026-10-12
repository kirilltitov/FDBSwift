extension FDB.Database {
    /// Waits until the value of given key changes (relative to its value at the moment of the call).
    ///
    /// A completed wait means that the value has *probably* changed: intermediate changes may be missed
    /// (`A → B → A` may complete it or not). Use ``changes(of:)`` to observe a key continuously.
    public func waitForChange(of key: some FDB.Key) async throws {
        let watch = try await self.withTransaction { tr in
            tr.watch(key: key)
        }
        try await watch.value
    }

    /// Returns an asynchronous sequence of values of given key: the current one first, then every new value as soon
    /// as it's committed.
    ///
    /// ```swift
    /// for try await config in db.changes(of: configKey) {
    ///     reload(config) // `nil` if the key doesn't exist
    /// }
    /// ```
    ///
    /// Built on watches (see ``FDB/Transaction/watch(key:)``), so it doesn't poll. Rapid successive changes may be
    /// coalesced: the sequence always delivers the latest value, but not necessarily every intermediate one, and
    /// never the same value twice in a row. Every active iteration holds one watch, see
    /// ``FDB/DatabaseOption/maxWatches(_:)``.
    ///
    /// The sequence ends only by throwing an error or when the iterating task is cancelled.
    public func changes(of key: some FDB.Key) -> FDB.Changes {
        FDB.Changes(database: self, key: key.fdbKey)
    }
}

extension FDB {
    /// Values of a key as they change, see ``FDB/Database/changes(of:)``
    public struct Changes: AsyncSequence, Sendable {
        public typealias Element = Bytes?

        let database: Database
        let key: Bytes

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(database: self.database, key: self.key)
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            let database: Database
            let key: Bytes
            private let state = State()

            init(database: Database, key: Bytes) {
                self.database = database
                self.key = key
            }

            /// Pending watch and the last delivered value. A class, because the watch is non-copyable and the iterator
            /// must be copyable.
            private final class State {
                var watch: Future<Void>?
                var lastValue: Bytes??
            }

            public mutating func next() async throws -> Bytes?? {
                while true {
                    if let watch = self.state.watch.take() {
                        do {
                            try await watch.value
                        } catch let error where error.isRetryable {
                            // The watch was lost (e.g. the cluster was recovering), just read and watch again
                        }
                    }

                    var value: Bytes?
                    self.state.watch = try await self.database.withTransaction { tr in
                        value = try await tr.get(key: self.key).value
                        return tr.watch(key: self.key)
                    }

                    if let lastValue = self.state.lastValue, lastValue == value {
                        // The watch has fired, but the value is the same (A → B → A, or a no-op write)
                        continue
                    }
                    self.state.lastValue = .some(value)
                    return .some(value)
                }
            }
        }
    }
}
