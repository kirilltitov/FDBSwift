import FDB
import Helpers
import Foundation

/// A protocol for anything that identifies something and can be represented as bytes
public protocol AnyIdentifier: Hashable {
    var _bytes: Bytes { get }
}

public extension AnyIdentifier {
    var _bytes: Bytes {
        getBytes(self)
    }
}

extension Int: AnyIdentifier {}
extension String: AnyIdentifier {}
extension UUID: AnyIdentifier {}

public extension FDB {
    struct ID<Value: Codable & Hashable>: AnyIdentifier {
        public let value: Value

        @inlinable public var _bytes: Bytes {
            getBytes(value)
        }

        public init(value: Value) {
            self.value = value
        }
    }
}
