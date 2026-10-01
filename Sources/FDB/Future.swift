import CFDB

extension FDB {
    /// A pending result of a FoundationDB operation.
    ///
    /// The request is sent to the cluster as soon as the future is created, so several futures can be in flight at
    /// once. This is the intended way of issuing parallel reads within a single transaction:
    ///
    /// ```swift
    /// let a = tr.get(key: keyA)
    /// let b = tr.get(key: keyB)
    /// let (valueA, valueB) = try await (a.value, b.value)
    /// ```
    ///
    /// A future is a non-copyable value with a single owner: it's awaited at most once (``value`` consumes it), and
    /// its underlying resources are released exactly once, when it's consumed or goes out of scope.
    /// Dropping a future without awaiting it is fine: the request result is simply discarded.
    ///
    /// If the awaiting task is cancelled, the future is cancelled too and ``value`` throws
    /// ``FDB/Error/operationCancelled``.
    public struct Future<Value>: ~Copyable {
        @usableFromInline
        let pointer: OpaquePointer

        @usableFromInline
        let extract: (OpaquePointer) throws(FDB.Error) -> Value

        @usableFromInline
        init(_ pointer: OpaquePointer, extract: @escaping (OpaquePointer) throws(FDB.Error) -> Value) {
            self.pointer = pointer
            self.extract = extract
        }

        deinit {
            fdb_future_destroy(self.pointer)
        }

        /// Whether the result is already available
        public var isReady: Bool {
            fdb_future_is_ready(self.pointer) != 0
        }

        /// Cancels the operation. Awaiting the future afterwards throws ``FDB/Error/operationCancelled``.
        public func cancel() {
            fdb_future_cancel(self.pointer)
        }

        /// Waits for the result.
        ///
        /// Consumes the future: its memory is released right after the value is extracted.
        public var value: Value {
            consuming get async throws(FDB.Error) {
                try await self.waitUntilReady()
                return try self.extractValue()
            }
        }

        /// Error of a ready future (if any) without extracting the value
        func readyError() -> FDB.Error? {
            let code = fdb_future_get_error(self.pointer)
            return code == 0 ? nil : FDB.Error(code: code)
        }

        func extractValue() throws(FDB.Error) -> Value {
            try fdb_future_get_error(self.pointer).check()
            return try self.extract(self.pointer)
        }

        func waitUntilReady() async throws(FDB.Error) {
            // Fast path: no need to bounce through the network thread if the result is already here
            if fdb_future_is_ready(self.pointer) != 0 {
                return
            }

            let handle = FutureHandle(self.pointer)
            let error: FDB.Error? = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<FDB.Error?, Never>) in
                    let box = Unmanaged.passRetained(ContinuationBox(continuation))
                    let code = fdb_future_set_callback(handle.pointer, { _, context in
                        Unmanaged<ContinuationBox>.fromOpaque(context!).takeRetainedValue().continuation.resume(returning: nil)
                    }, box.toOpaque())
                    if code != 0 {
                        // The callback will never be called, so it's our job to release the box
                        box.release()
                        continuation.resume(returning: FDB.Error(code: code))
                    }
                }
            } onCancel: {
                fdb_future_cancel(handle.pointer)
            }

            if let error {
                throw error
            }
        }
    }
}

/// Sendable wrapper for the future pointer: FDB futures are thread-safe, so it's safe to cancel one from any thread
private struct FutureHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }
}

private final class ContinuationBox: Sendable {
    let continuation: CheckedContinuation<FDB.Error?, Never>

    init(_ continuation: CheckedContinuation<FDB.Error?, Never>) {
        self.continuation = continuation
    }
}

// MARK: - Value extractors

extension FDB.Future where Value == Void {
    init(_ pointer: OpaquePointer) {
        self.init(pointer) { (_) throws(FDB.Error) in }
    }
}

extension FDB.Future where Value == Bytes? {
    /// Future of `fdb_transaction_get`
    static func optionalBytes(_ pointer: OpaquePointer) -> Self {
        Self(pointer) { (pointer) throws(FDB.Error) -> Bytes? in
            var present: fdb_bool_t = 0
            var value: UnsafePointer<UInt8>?
            var length: Int32 = 0
            try fdb_future_get_value(pointer, &present, &value, &length).check()
            guard present != 0 else {
                return nil
            }
            return Bytes(UnsafeBufferPointer(start: value, count: Int(length)))
        }
    }
}

extension FDB.Future where Value == Bytes {
    /// Future of `fdb_transaction_get_key` and `fdb_transaction_get_versionstamp`
    static func key(_ pointer: OpaquePointer) -> Self {
        Self(pointer) { (pointer) throws(FDB.Error) -> Bytes in
            var key: UnsafePointer<UInt8>?
            var length: Int32 = 0
            try fdb_future_get_key(pointer, &key, &length).check()
            return Bytes(UnsafeBufferPointer(start: key, count: Int(length)))
        }
    }
}

extension FDB.Future where Value == Int64 {
    /// Future of `fdb_transaction_get_read_version`, `fdb_transaction_get_approximate_size` etc.
    static func int64(_ pointer: OpaquePointer) -> Self {
        Self(pointer) { (pointer) throws(FDB.Error) -> Int64 in
            var value: Int64 = 0
            try fdb_future_get_int64(pointer, &value).check()
            return value
        }
    }
}
