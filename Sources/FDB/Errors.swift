public extension FDB {
    public enum Error: Swift.Error {
        case APIError(String, Int32)
        case NetworkError(String, Int32)
        case ClusterError(String, Int32)
        case DBError(String, Int32)
    }
}

public extension Transaction {
    public enum Error: Swift.Error {
        case BeginError(String, Int32)
        case CommitError(String, Int32)
        case GetError(String, Int32)
        case Retry(String)
    }
}
