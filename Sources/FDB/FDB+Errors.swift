import CFDB

public extension FDB {
    /// Internal FDB error type (`fdb_error_t` aka `Int32`)
    public typealias Errno = fdb_error_t
}

extension FDB.Errno {
    /// Converts non-zero error number to throwable error
    public func orThrow() throws {
        if self == 0 {
            return
        }
        throw FDB.Error.from(errno: self)
    }

    /// Converts non-zero error number to fatal runtime error
    public func orDie() {
        try! self.orThrow()
    }
}

public extension FDB {
    /// Error type for both FDB errors and FDBSwift errors
    public enum Error: Errno, Swift.Error {
        case operationFailed                        = 1000
        case timedOut                               = 1004
        case transactionTooOld                      = 1007
        case futureVersion                          = 1009
        case notCommitted                           = 1020
        case commitUnknownResult                    = 1021
        case transactionCancelled                   = 1025
        case transactionTimedOut                    = 1031
        case tooManyWatches                         = 1032
        case watchesDisabled                        = 1034
        case accessedUnreadable                     = 1036
        case databaseLocked                         = 1038
        case clusterVersionChanged                  = 1039
        case externalClientAlreadyLoaded            = 1040
        case operationCancelled                     = 1101
        case futureReleased                         = 1102
        case platformError                          = 1500
        case largeAllocFailed                       = 1501
        case performanceCounterError                = 1502
        case IOError                                = 1510
        case fileNotFound                           = 1511
        case bindFailed                             = 1512
        case fileNotReadable                        = 1513
        case fileNotWritable                        = 1514
        case noClusterFileFound                     = 1515
        case fileTooLarge                           = 1516
        case clientInvalidOperation                 = 2000
        case commitReadIncomplete                   = 2002
        case testSpecificationInvalid               = 2003
        case keyOutsideLegalRange                   = 2004
        case invertedRange                          = 2005
        case invalidOptionValue                     = 2006
        case invalidOption                          = 2007
        case networkNotSetup                        = 2008
        case networkAlreadySetup                    = 2009
        case readVersionAlreadySet                  = 2010
        case versionInvalid                         = 2011
        case rangeLimitsInvalid                     = 2012
        case invalidDatabaseName                    = 2013
        case attributeNotFound                      = 2014
        case futureNotSet                           = 2015
        case futureNotError                         = 2016
        case usedDuringCommit                       = 2017
        case invalidMutationType                    = 2018
        case transactionInvalidVersion              = 2020
        case transactionReadOnly                    = 2021 // Transaction is read-only and therefore does not have a commit version
        case environmentVariableNetworkOptionFailed = 2022
        case transactionReadOnly2                   = 2023 // Attempted to commit a transaction specified as read-only
        case incompatibleProtocolVersion            = 2100
        case transactionTooLarge                    = 2101
        case keyTooLarge                            = 2102
        case valueTooLarge                          = 2103
        case connectionStringInvalid                = 2104
        case addressInUse                           = 2105
        case invalidLocalAddress                    = 2106
        case TLSError                               = 2107
        case unsupportedOperation                   = 2108
        case APIVersionUnset                        = 2200
        case APIVersionAlreadySet                   = 2201
        case APIVersionInvalid                      = 2202
        case APIVersionNotSupported                 = 2203
        case exactModeWithoutLimits                 = 2210
        case unknownError                           = 4000

        case transactionRetry = 8000
        case unexpectedError = 9000
        case noEventLoopProvided = 9500
        case connectionError = 9600
        case unpackEmptyInput = 9701
        case unpackTooLargeInt = 9702
        case unpackUnknownCode = 9703
        case unpackInvalidBoundaries = 9704
        case unpackInvalidString = 9705

        /// Returns and instance of FDB.Error from FDB error number
        public static func from(errno: FDB.Errno) -> Error {
            guard let error = FDB.Error(rawValue: errno) else {
                FDB.debug("Unexpected error \(errno)")
                return FDB.Error.unexpectedError
            }
            return error
        }

        /// Returns human-readable description of current FDB error
        public func getDescription() -> String {
            if self.rawValue == 8000 {
                return "You should replay this transaction"
            }
            if self.rawValue == 9000 {
                return "Error is unexpected, it shouldn't really happen"
            }
            return FDB.Error.getErrorInfo(for: self.rawValue)
        }

        /// Returns FDB error description from error number
        private static func getErrorInfo(for errno: fdb_error_t) -> String {
            return String(cString: fdb_get_error(errno))
        }
    }
}
