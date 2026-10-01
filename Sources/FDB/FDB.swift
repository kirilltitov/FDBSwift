import CFDB

/// Namespace for the FoundationDB client.
///
/// Entry point is ``FDB/Database``:
///
/// ```swift
/// let db = try FDB.Database()
/// try await db.withTransaction { tr in
///     tr.set(key: "hello", value: Bytes("world".utf8))
/// }
/// ```
public enum FDB {
    /// FoundationDB C API version this package is built against
    public static let apiVersion: Int32 = FDB_API_VERSION
}

public typealias Byte = UInt8
public typealias Bytes = [Byte]
