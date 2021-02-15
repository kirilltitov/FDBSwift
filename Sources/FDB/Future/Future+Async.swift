import _Concurrency

internal extension FDB.Future {
    func ready() async throws -> Self {
        let _ = try await self.void()

        return self
    }

    func void() async throws -> Void {
        return try await withUnsafeThrowingContinuation { continuation in
            self.whenVoidReady(continuation.resume(returning:))
            self.whenError(continuation.resume(throwing:))
        }
    }

    func keyBytes() async throws -> Bytes {
        return try await withUnsafeThrowingContinuation { continuation in
            self.whenKeyBytesReady(continuation.resume(returning:))
            self.whenError(continuation.resume(throwing:))
        }
    }

    func bytes() async throws -> Bytes? {
        return try await withUnsafeThrowingContinuation { continuation in
            self.whenBytesReady(continuation.resume(returning:))
            self.whenError(continuation.resume(throwing:))
        }
    }

    func int64() async throws -> Int64 {
        return try await withUnsafeThrowingContinuation { continuation in
            self.whenInt64Ready(continuation.resume(returning:))
            self.whenError(continuation.resume(throwing:))
        }
    }

    func keyValues() async throws -> FDB.KeyValuesResult {
        return try await withUnsafeThrowingContinuation { continuation in
            self.whenKeyValuesReady(continuation.resume(returning:))
            self.whenError(continuation.resume(throwing:))
        }
    }
}
