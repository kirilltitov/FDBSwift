public import FDB
public import Foundation

extension FDB {
    /// A wrapper identifier of entities
    public struct ID<Value: Hashable & Sendable>: Hashable, Sendable {
        public let value: Value

        public init(value: Value) {
            self.value = value
        }
    }

    /// UUID identifier of entities.
    ///
    /// Packed into keys as a byte string with the 16 bytes of the UUID (not as a tuple UUID) and serialized as `Data`
    /// (a Base64 string in JSON), like in Entita2.
    public typealias UUID = ID<Foundation.UUID>
}

public extension FDB.ID where Value == Foundation.UUID {
    /// A new random UUID
    init() {
        self.init(value: Foundation.UUID())
    }

    init(_ uuid: Foundation.UUID) {
        self.init(value: uuid)
    }

    init?(_ string: String) {
        guard let uuid = Foundation.UUID(uuidString: string) else {
            return nil
        }
        self.init(value: uuid)
    }

    /// Creates a UUID from its 16 bytes
    init?(bytes: some Collection<UInt8>) {
        guard bytes.count == 16 else {
            return nil
        }
        let uuid = Bytes(bytes).withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) }
        self.init(value: Foundation.UUID(uuid: uuid))
    }

    var string: String {
        self.value.uuidString
    }

    /// The 16 bytes of the UUID
    var bytes: Bytes {
        withUnsafeBytes(of: self.value.uuid) { Bytes($0) }
    }
}

extension FDB.ID: FDB.TuplePackable where Value == Foundation.UUID {
    public func pack(into encoder: inout FDB.TupleEncoder) {
        encoder.appendBytes(self.bytes)
    }
}

extension FDB.ID: FDB.TupleUnpackable where Value == Foundation.UUID {
    public init(tupleElement: FDB.TupleElement) throws(FDB.Error) {
        guard case let .bytes(bytes) = tupleElement, let id = Self(bytes: bytes) else {
            throw .unpackTypeMismatch
        }
        self = id
    }
}

extension FDB.ID: Codable where Value == Foundation.UUID {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        guard let id = Self(bytes: data) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "UUID must be 16 bytes long, got \(data.count)"
            )
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Data(self.bytes))
    }
}

extension FDB.ID: CustomStringConvertible where Value == Foundation.UUID {
    public var description: String {
        self.string
    }
}
