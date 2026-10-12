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
    /// Latest FoundationDB C API version supported by this package (the version of the C headers it's built against),
    /// used unless another one is selected with ``FDB/Network/selectAPIVersion(_:)``
    public static let latestAPIVersion: Int32 = FDB_API_VERSION

    /// Oldest FoundationDB C API version supported by this package.
    ///
    /// API 630 allows working with FoundationDB 6.3 clusters via the multi-version client, see
    /// ``FDB/Network/selectAPIVersion(_:)``.
    public static let minimumAPIVersion: Int32 = 630

    /// API version in use: the one selected with ``FDB/Network/selectAPIVersion(_:)``, or ``latestAPIVersion``
    public static var apiVersion: Int32 {
        Network.apiVersion
    }

    /// Throws ``FDB/Error/unsupportedOperation`` if the API version in use is older than given one
    @inline(__always)
    static func requireAPIVersion(_ version: Int32) throws(FDB.Error) {
        if Network.apiVersion < version {
            throw .unsupportedOperation
        }
    }
}

public typealias Byte = UInt8
public typealias Bytes = [Byte]
