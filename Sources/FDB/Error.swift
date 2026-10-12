import CFDB

extension FDB {
    /// An error returned by FoundationDB or by this package.
    ///
    /// Native FoundationDB errors carry the original code from the C client (see
    /// [error codes](https://apple.github.io/foundationdb/api-error-codes.html)), so no information is lost even
    /// for codes this package doesn't know about. Errors specific to this package have codes in
    /// ``bindingErrorCodes`` range.
    ///
    /// Errors can be matched with `catch`:
    ///
    /// ```swift
    /// do { ... } catch FDB.Error.transactionTooOld { ... }
    /// ```
    public struct Error: Swift.Error, Hashable, Sendable, CustomStringConvertible {
        /// Raw error code
        public let code: Int32

        /// Range of codes used by this package for its own errors
        public static let bindingErrorCodes: ClosedRange<Int32> = 9000 ... 9999

        @inlinable
        public init(code: Int32) {
            self.code = code
        }

        /// Whether this error was produced by FoundationDB itself (not by this package)
        public var isNative: Bool {
            !Self.bindingErrorCodes.contains(self.code)
        }

        /// The transaction should be retried because of a transient error
        public var isRetryable: Bool {
            self.isNative && fdb_error_predicate(Int32(FDB_ERROR_PREDICATE_RETRYABLE.rawValue), self.code) != 0
        }

        /// The transaction may have been committed, though it's impossible to verify
        public var isMaybeCommitted: Bool {
            self.isNative && fdb_error_predicate(Int32(FDB_ERROR_PREDICATE_MAYBE_COMMITTED.rawValue), self.code) != 0
        }

        /// The transaction definitely has not been committed and can be retried
        public var isRetryableNotCommitted: Bool {
            self.isNative
                && fdb_error_predicate(Int32(FDB_ERROR_PREDICATE_RETRYABLE_NOT_COMMITTED.rawValue), self.code) != 0
        }

        /// Human-readable description of the error
        public var message: String {
            switch self.code {
            case Self.unpackInvalidInput.code: "Invalid tuple input"
            case Self.unpackUnknownCode.code: "Unknown or unsupported tuple type code"
            case Self.unpackTooLargeInt.code: "Tuple integer doesn't fit into requested type"
            case Self.unpackInvalidString.code: "Tuple string is not valid UTF-8"
            case Self.unpackTooDeep.code: "Tuple nesting is too deep"
            case Self.unpackTypeMismatch.code: "Tuple element has unexpected type"
            case Self.missingIncompleteVersionstamp.code: "No incomplete versionstamp found in the key"
            case Self.multipleIncompleteVersionstamps.code: "More than one incomplete versionstamp in the key"
            case Self.invalidVersionstamp.code: "Invalid versionstamp"
            case Self.networkNotStarted.code: "Network is not started"
            case Self.networkStopped.code: "Network has been stopped and can't be restarted within the process"
            default: String(cString: fdb_get_error(self.code))
            }
        }

        public var description: String {
            "FDB.Error(\(self.code): \(self.message))"
        }
    }
}

// MARK: - Well-known FoundationDB errors

public extension FDB.Error {
    static let operationFailed = Self(code: 1000)
    static let timedOut = Self(code: 1004)
    static let transactionTooOld = Self(code: 1007)
    static let futureVersion = Self(code: 1009)
    static let notCommitted = Self(code: 1020)
    static let commitUnknownResult = Self(code: 1021)
    static let transactionCancelled = Self(code: 1025)
    static let transactionTimedOut = Self(code: 1031)
    static let tooManyWatches = Self(code: 1032)
    static let watchesDisabled = Self(code: 1034)
    static let accessedUnreadable = Self(code: 1036)
    static let processBehind = Self(code: 1037)
    static let databaseLocked = Self(code: 1038)
    static let clusterVersionChanged = Self(code: 1039)
    static let externalClientAlreadyLoaded = Self(code: 1040)
    static let proxyMemoryLimitExceeded = Self(code: 1042)
    static let batchTransactionThrottled = Self(code: 1051)
    static let tagThrottled = Self(code: 1213)
    static let operationCancelled = Self(code: 1101)
    static let futureReleased = Self(code: 1102)
    static let platformError = Self(code: 1500)
    static let ioError = Self(code: 1510)
    static let fileNotFound = Self(code: 1511)
    static let noClusterFileFound = Self(code: 1515)
    static let clientInvalidOperation = Self(code: 2000)
    static let commitReadIncomplete = Self(code: 2002)
    static let keyOutsideLegalRange = Self(code: 2004)
    static let invertedRange = Self(code: 2005)
    static let invalidOptionValue = Self(code: 2006)
    static let invalidOption = Self(code: 2007)
    static let networkNotSetup = Self(code: 2008)
    static let networkAlreadySetup = Self(code: 2009)
    static let readVersionAlreadySet = Self(code: 2010)
    static let versionInvalid = Self(code: 2011)
    static let rangeLimitsInvalid = Self(code: 2012)
    static let usedDuringCommit = Self(code: 2017)
    static let invalidMutationType = Self(code: 2018)
    static let transactionReadOnly = Self(code: 2023)
    static let incompatibleProtocolVersion = Self(code: 2100)
    static let transactionTooLarge = Self(code: 2101)
    static let keyTooLarge = Self(code: 2102)
    static let valueTooLarge = Self(code: 2103)
    static let connectionStringInvalid = Self(code: 2104)
    static let tlsError = Self(code: 2107)
    static let apiVersionUnset = Self(code: 2200)
    static let apiVersionAlreadySet = Self(code: 2201)
    static let apiVersionInvalid = Self(code: 2202)
    static let apiVersionNotSupported = Self(code: 2203)
    static let exactModeWithoutLimits = Self(code: 2210)
    static let unknownError = Self(code: 4000)
    static let internalError = Self(code: 4100)
}

// MARK: - Errors specific to this package

public extension FDB.Error {
    static let unpackInvalidInput = Self(code: 9701)
    static let unpackTooLargeInt = Self(code: 9702)
    static let unpackUnknownCode = Self(code: 9703)
    static let unpackInvalidString = Self(code: 9705)
    static let unpackTooDeep = Self(code: 9706)
    static let unpackTypeMismatch = Self(code: 9707)
    static let missingIncompleteVersionstamp = Self(code: 9800)
    static let invalidVersionstamp = Self(code: 9801)
    static let multipleIncompleteVersionstamps = Self(code: 9802)
    static let networkNotStarted = Self(code: 9900)
    static let networkStopped = Self(code: 9901)
}

extension fdb_error_t {
    /// Throws if current error code is non-zero
    @inline(__always)
    func check() throws(FDB.Error) {
        if self != 0 {
            throw FDB.Error(code: self)
        }
    }
}
