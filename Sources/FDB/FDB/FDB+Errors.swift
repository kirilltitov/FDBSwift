import CFDB
import LGNLog

public extension FDB {
    /// Internal FDB error type (`fdb_error_t` aka `Int32`)
    typealias Errno = fdb_error_t
}

internal extension FDB.Errno {
    /// Converts non-zero error number to throwable error
    @inlinable
    func orThrow() throws {
        if case let .failure(error) = self.toResult() {
            throw error
        }
    }

    @inlinable
    func toResult() -> Result<Void, FDB.Error> {
        if self == 0 {
            return .success(())
        }

        return .failure(FDB.Error.from(errno: self))
    }

    /// Converts non-zero error number to fatal runtime error
    @inlinable
    func orDie() {
        try! self.orThrow()
    }
}

public extension FDB {
    /// Error type for both FDB errors and FDBSwift errors
    enum Error: Swift.Error {
        case operationFailed
        case timedOut
        case transactionTooOld
        case futureVersion
        case notCommitted
        case commitUnknownResult
        case transactionCancelled
        case transactionTimedOut
        case tooManyWatches
        case watchesDisabled
        case accessedUnreadable
        case databaseLocked
        case clusterVersionChanged
        case externalClientAlreadyLoaded
        case operationCancelled
        case futureReleased
        case platformError
        case largeAllocFailed
        case performanceCounterError
        case IOError
        case fileNotFound
        case bindFailed
        case fileNotReadable
        case fileNotWritable
        case noClusterFileFound
        case fileTooLarge
        case clientInvalidOperation
        case commitReadIncomplete
        case testSpecificationInvalid
        case keyOutsideLegalRange
        case invertedRange
        case invalidOptionValue
        case invalidOption
        case networkNotSetup
        case networkAlreadySetup
        case readVersionAlreadySet
        case versionInvalid
        case rangeLimitsInvalid
        case invalidDatabaseName
        case attributeNotFound
        case futureNotSet
        case futureNotError
        case usedDuringCommit
        case invalidMutationType
        case transactionInvalidVersion
        case transactionReadOnly // Transaction is read-only and therefore does not have a commit version
        case environmentVariableNetworkOptionFailed
        case transactionReadOnly2 // Attempted to commit a transaction specified as read-only
        case incompatibleProtocolVersion
        case transactionTooLarge
        case keyTooLarge
        case valueTooLarge
        case connectionStringInvalid
        case addressInUse
        case invalidLocalAddress
        case TLSError
        case unsupportedOperation
        case APIVersionUnset
        case APIVersionAlreadySet
        case APIVersionInvalid
        case APIVersionNotSupported
        case exactModeWithoutLimits
        case unknownError
        case internalError

        case transactionRetry
        case unexpectedError(String)
        case noEventLoopProvided
        case connectionError
        case unpackEmptyInput
        case unpackTooLargeInt
        case unpackUnknownCode
        case unpackInvalidBoundaries
        case unpackInvalidString
        
        case missingIncompleteVersionstamp
        case invalidVersionstamp

        /// Returns and instance of FDB.Error from FDB error number
        public static func from(errno: FDB.Errno) -> Error {
            let result: FDB.Error
            switch errno {
            case 1000: result = .operationFailed
            case 1004: result = .timedOut
            case 1007: result = .transactionTooOld
            case 1009: result = .futureVersion
            case 1020: result = .notCommitted
            case 1021: result = .commitUnknownResult
            case 1025: result = .transactionCancelled
            case 1031: result = .transactionTimedOut
            case 1032: result = .tooManyWatches
            case 1034: result = .watchesDisabled
            case 1036: result = .accessedUnreadable
            case 1038: result = .databaseLocked
            case 1039: result = .clusterVersionChanged
            case 1040: result = .externalClientAlreadyLoaded
            case 1101: result = .operationCancelled
            case 1102: result = .futureReleased
            case 1500: result = .platformError
            case 1501: result = .largeAllocFailed
            case 1502: result = .performanceCounterError
            case 1510: result = .IOError
            case 1511: result = .fileNotFound
            case 1512: result = .bindFailed
            case 1513: result = .fileNotReadable
            case 1514: result = .fileNotWritable
            case 1515: result = .noClusterFileFound
            case 1516: result = .fileTooLarge
            case 2000: result = .clientInvalidOperation
            case 2002: result = .commitReadIncomplete
            case 2003: result = .testSpecificationInvalid
            case 2004: result = .keyOutsideLegalRange
            case 2005: result = .invertedRange
            case 2006: result = .invalidOptionValue
            case 2007: result = .invalidOption
            case 2008: result = .networkNotSetup
            case 2009: result = .networkAlreadySetup
            case 2010: result = .readVersionAlreadySet
            case 2011: result = .versionInvalid
            case 2012: result = .rangeLimitsInvalid
            case 2013: result = .invalidDatabaseName
            case 2014: result = .attributeNotFound
            case 2015: result = .futureNotSet
            case 2016: result = .futureNotError
            case 2017: result = .usedDuringCommit
            case 2018: result = .invalidMutationType
            case 2020: result = .transactionInvalidVersion
            case 2021: result = .transactionReadOnly
            case 2022: result = .environmentVariableNetworkOptionFailed
            case 2023: result = .transactionReadOnly2
            case 2100: result = .incompatibleProtocolVersion
            case 2101: result = .transactionTooLarge
            case 2102: result = .keyTooLarge
            case 2103: result = .valueTooLarge
            case 2104: result = .connectionStringInvalid
            case 2105: result = .addressInUse
            case 2106: result = .invalidLocalAddress
            case 2107: result = .TLSError
            case 2108: result = .unsupportedOperation
            case 2200: result = .APIVersionUnset
            case 2201: result = .APIVersionAlreadySet
            case 2202: result = .APIVersionInvalid
            case 2203: result = .APIVersionNotSupported
            case 2210: result = .exactModeWithoutLimits
            case 4000: result = .unknownError
            case 4100: result = .internalError
            case 9500: result = .noEventLoopProvided
            case 9600: result = .connectionError
            case 9701: result = .unpackEmptyInput
            case 9702: result = .unpackTooLargeInt
            case 9703: result = .unpackUnknownCode
            case 9704: result = .unpackInvalidBoundaries
            case 9705: result = .unpackInvalidString
            case 9800: result = .missingIncompleteVersionstamp
            case 9801: result = .invalidVersionstamp
            default:
            Logger.current.error("Unknown errno \(errno)")
            result = .unknownError
            }

            return result
        }

        public var errno: Errno {
            let result: Errno
            switch self {
            case .operationFailed:                        result = 1000
            case .timedOut:                               result = 1004
            case .transactionTooOld:                      result = 1007
            case .futureVersion:                          result = 1009
            case .notCommitted:                           result = 1020
            case .commitUnknownResult:                    result = 1021
            case .transactionCancelled:                   result = 1025
            case .transactionTimedOut:                    result = 1031
            case .tooManyWatches:                         result = 1032
            case .watchesDisabled:                        result = 1034
            case .accessedUnreadable:                     result = 1036
            case .databaseLocked:                         result = 1038
            case .clusterVersionChanged:                  result = 1039
            case .externalClientAlreadyLoaded:            result = 1040
            case .operationCancelled:                     result = 1101
            case .futureReleased:                         result = 1102
            case .platformError:                          result = 1500
            case .largeAllocFailed:                       result = 1501
            case .performanceCounterError:                result = 1502
            case .IOError:                                result = 1510
            case .fileNotFound:                           result = 1511
            case .bindFailed:                             result = 1512
            case .fileNotReadable:                        result = 1513
            case .fileNotWritable:                        result = 1514
            case .noClusterFileFound:                     result = 1515
            case .fileTooLarge:                           result = 1516
            case .clientInvalidOperation:                 result = 2000
            case .commitReadIncomplete:                   result = 2002
            case .testSpecificationInvalid:               result = 2003
            case .keyOutsideLegalRange:                   result = 2004
            case .invertedRange:                          result = 2005
            case .invalidOptionValue:                     result = 2006
            case .invalidOption:                          result = 2007
            case .networkNotSetup:                        result = 2008
            case .networkAlreadySetup:                    result = 2009
            case .readVersionAlreadySet:                  result = 2010
            case .versionInvalid:                         result = 2011
            case .rangeLimitsInvalid:                     result = 2012
            case .invalidDatabaseName:                    result = 2013
            case .attributeNotFound:                      result = 2014
            case .futureNotSet:                           result = 2015
            case .futureNotError:                         result = 2016
            case .usedDuringCommit:                       result = 2017
            case .invalidMutationType:                    result = 2018
            case .transactionInvalidVersion:              result = 2020
            case .transactionReadOnly:                    result = 2021
            case .environmentVariableNetworkOptionFailed: result = 2022
            case .transactionReadOnly2:                   result = 2023
            case .incompatibleProtocolVersion:            result = 2100
            case .transactionTooLarge:                    result = 2101
            case .keyTooLarge:                            result = 2102
            case .valueTooLarge:                          result = 2103
            case .connectionStringInvalid:                result = 2104
            case .addressInUse:                           result = 2105
            case .invalidLocalAddress:                    result = 2106
            case .TLSError:                               result = 2107
            case .unsupportedOperation:                   result = 2108
            case .APIVersionUnset:                        result = 2200
            case .APIVersionAlreadySet:                   result = 2201
            case .APIVersionInvalid:                      result = 2202
            case .APIVersionNotSupported:                 result = 2203
            case .exactModeWithoutLimits:                 result = 2210
            case .unknownError:                           result = 4000
            case .internalError:                          result = 4100
            case .transactionRetry:                       result = 8000
            case .unexpectedError:                        result = 9000
            case .noEventLoopProvided:                    result = 9500
            case .connectionError:                        result = 9600
            case .unpackEmptyInput:                       result = 9701
            case .unpackTooLargeInt:                      result = 9702
            case .unpackUnknownCode:                      result = 9703
            case .unpackInvalidBoundaries:                result = 9704
            case .unpackInvalidString:                    result = 9705
            case .missingIncompleteVersionstamp:          result = 9800
            case .invalidVersionstamp:                    result = 9801
            }

            return result
        }

        /// Indicates if current error is a native FoundationDB error
        /// (i.e. errno is less than `8000`, after which custom FDBSwift errors start)
        internal var isNative: Bool {
            self.errno < 8000
        }

        /// Returns human-readable description of current FDB error
        public func getDescription() -> String {
            if self.errno == 8000 {
                return "You should replay this transaction"
            }
            if self.errno == 9000 {
                return "Error is unexpected, it shouldn't really happen"
            }
            return FDB.Error.getErrorInfo(for: self.errno)
        }

        /// Returns FDB error description from error number
        public static func getErrorInfo(for errno: fdb_error_t) -> String {
            return String(cString: fdb_get_error(errno))
        }
    }
}
