public extension FDB {
    public enum Error: Swift.Error {
        case ApiError(String, Int32)
        case NetworkError(String, Int32)
        case ClusterError(String, Int32)
        case DBError(String, Int32)
    }
}

public extension Transaction {
    public enum Error: Swift.Error {
        case TransactionBeginError(String, Int32)
        case TransactionCommitError(String, Int32)
        case TransactionRetry(String)
        case TransactionGetError(String, Int32)
    }
}
