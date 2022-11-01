import FDB

public extension FDB.Entity {
    enum Error: Swift.Error {
        case SaveError(String)
        case IndexError(String)
        case CastError(String)
    }
}
