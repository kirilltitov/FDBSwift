@testable import FDB
import Foundation

/// Test setup shared by all suites.
///
/// The whole suite can be run against an older cluster with an older API version, e.g. FoundationDB 6.3 via the
/// multi-version client:
///
/// ```bash
/// FDB_TEST_API_VERSION=630 FDB_NETWORK_OPTION_EXTERNAL_CLIENT_DIRECTORY=/path/to/6.3/libs \
///     FDB_CLUSTER_FILE=/path/to/6.3/fdb.cluster swift test
/// ```
///
/// Tests of features newer than the selected API version are skipped.
enum TestEnvironment {
    /// API version the tests run with
    static let apiVersion: Int32 = ProcessInfo.processInfo.environment["FDB_TEST_API_VERSION"]
        .flatMap { Int32($0) } ?? FDB.latestAPIVersion

    /// Must be touched before anything starts the network
    static let ready: Void = {
        if apiVersion != FDB.latestAPIVersion {
            try! FDB.Network.selectAPIVersion(apiVersion)
        }
    }()

    static func makeDatabase(transactionRetryLimit: Int64? = FDB.Database.defaultTransactionRetryLimit) throws -> FDB.Database {
        _ = self.ready
        return try FDB.Database(transactionRetryLimit: transactionRetryLimit)
    }
}
