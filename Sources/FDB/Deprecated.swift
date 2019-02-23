import CFDB
import Dispatch

@available(*, unavailable, renamed: "AnyFDBKey")
public typealias FDBKey = AnyFDBKey

public extension FDB {
    @available(*, deprecated, message: "Use init without queue argument")
    public convenience init(
        cluster: String? = nil,
        networkStopTimeout: Int = 10,
        version: Int32 = FDB_API_VERSION,
        queue: DispatchQueue = DispatchQueue(label: "fdb", qos: .userInitiated, attributes: .concurrent)
    ) {
        self.init(cluster: cluster, networkStopTimeout: networkStopTimeout)
    }
}
