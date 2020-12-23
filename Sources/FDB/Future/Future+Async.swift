internal extension FDB.Future {
    func ready() async throws -> Self {
        let _ = try await self.void()

        return self
    }

    @inlinable
    var errno: FDB.Errno {
        let result: FDB.Errno

        switch self.state {
        case .Error(let errno): result = errno
        default: result = 0
        }

        return result
    }

    @inlinable
    func resolvedThrowing() async throws {
        try await self.resolved()

        let errno = self.errno
        if errno > 0 {
            throw FDB.Error.from(errno: errno)
        }
    }

    @inlinable
    func void() async throws {
        try await self.resolvedThrowing()
    }

    @inlinable
    func keyBytes() async throws -> Bytes {
        try await self.resolvedThrowing()

        return try self.parseKeyBytes()
    }

    @inlinable
    func bytes() async throws -> Bytes? {
        try await self.resolvedThrowing()

        return try self.parseBytes()
    }

    @inlinable
    func int64() async throws -> Int64 {
        try await self.resolvedThrowing()

        return try self.getVersion()
    }

    @inlinable
    func keyValues() async throws -> FDB.KeyValuesResult {
        try await self.resolvedThrowing()

        return try self.parseKeyValues()
    }
}
