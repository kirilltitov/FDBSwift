import LGNLog

public extension FDB.Connector {
    @available(*, deprecated, message: "Use Logger.current instead")
    static var logger: Logger = Logging.Logger(label: "FDB.Connector")
}

@available(*, deprecated, renamed: "FDBKey")
public typealias AnyFDBKey = FDBKey

@available(*, deprecated, renamed: "FDBConnector")
public typealias AnyFDB = FDBConnector

@available(*, deprecated, renamed: "FDBTransaction")
public typealias AnyFDBTransaction = FDBTransaction
