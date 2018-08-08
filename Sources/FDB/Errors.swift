import CFDB

public typealias Errno = fdb_error_t

extension Errno {
    public func orThrow() throws -> Void {
        if self == 0 {
            return
        }
        throw FDB.Error.from(errno: self)
    }

    public func orDie() {
        try! self.orThrow()
    }
}

public extension FDB {
    public enum Error: Errno, Swift.Error {
        case OperationFailed                        = 1000
        case TimedOut                               = 1004
        case TransactionTooOld                      = 1007
        case FutureVersion                          = 1009
        case NotCommitted                           = 1020
        case CommitUnknownResult                    = 1021
        case TransactionCancelled                   = 1025
        case TransactionTimedOut                    = 1031
        case TooManyWatches                         = 1032
        case WatchesDisabled                        = 1034
        case AccessedUnreadable                     = 1036
        case DatabaseLocked                         = 1038
        case ClusterVersionChanged                  = 1039
        case ExternalClientAlreadyLoaded            = 1040
        case OperationCancelled                     = 1101
        case FutureReleased                         = 1102
        case PlatformError                          = 1500
        case LargeAllocFailed                       = 1501
        case PerformanceCounterError                = 1502
        case IoError                                = 1510
        case FileNotFound                           = 1511
        case BindFailed                             = 1512
        case FileNotReadable                        = 1513
        case FileNotWritable                        = 1514
        case NoClusterFileFound                     = 1515
        case FileTooLarge                           = 1516
        case ClientInvalidOperation                 = 2000
        case CommitReadIncomplete                   = 2002
        case TestSpecificationInvalid               = 2003
        case KeyOutsideLegalRange                   = 2004
        case InvertedRange                          = 2005
        case InvalidOptionValue                     = 2006
        case InvalidOption                          = 2007
        case NetworkNotSetup                        = 2008
        case NetworkAlreadySetup                    = 2009
        case ReadVersionAlreadySet                  = 2010
        case VersionInvalid                         = 2011
        case RangeLimitsInvalid                     = 2012
        case InvalidDatabaseName                    = 2013
        case AttributeNotFound                      = 2014
        case FutureNotSet                           = 2015
        case FutureNotError                         = 2016
        case UsedDuringCommit                       = 2017
        case InvalidMutationType                    = 2018
        case TransactionInvalidVersion              = 2020
        case TransactionReadOnly                    = 2021 // Transaction is read-only and therefore does not have a commit version
        case EnvironmentVariableNetworkOptionFailed = 2022
        case TransactionReadOnly2                   = 2023 // Attempted to commit a transaction specified as read-only
        case IncompatibleProtocolVersion            = 2100
        case TransactionTooLarge                    = 2101
        case KeyTooLarge                            = 2102
        case ValueTooLarge                          = 2103
        case ConnectionStringInvalid                = 2104
        case AddressInUse                           = 2105
        case InvalidLocalAddress                    = 2106
        case TlsError                               = 2107
        case UnsupportedOperation                   = 2108
        case ApiVersionUnset                        = 2200
        case ApiVersionAlreadySet                   = 2201
        case ApiVersionInvalid                      = 2202
        case ApiVersionNotSupported                 = 2203
        case ExactModeWithoutLimits                 = 2210
        case UnknownError                           = 4000

        case TransactionRetry = 8000
        case UnexpectedError = 9000
        case NoEventLoopProvided = 9500

        public static func from(errno: Errno) -> Error {
            guard let error = Error(rawValue: errno) else {
                print("Unexpected error \(errno)")
                return Error.UnexpectedError
            }
            return error
        }

        public func getDescription() -> String {
            if self.rawValue == 8000 {
                return "You should replay this transaction"
            }
            if self.rawValue == 9000 {
                return "Error is unexpected, it shouldn't really happen"
            }
            return Error.getErrorInfo(for: self.rawValue)
        }

        private static func getErrorInfo(for errno: fdb_error_t) -> String {
            return String(cString: fdb_get_error(errno))
        }
    }
}
