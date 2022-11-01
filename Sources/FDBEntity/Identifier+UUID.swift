import Foundation
import FDB
import Helpers

public extension FDB {
    typealias UUID = ID<Foundation.UUID>
}

extension FDB.UUID: FDBTuplePackable {
    public var string: String {
        value.uuidString
    }

    public init(_ uuid: UUID = UUID()) {
        self.init(value: uuid)
    }

    public init?(_ string: String) {
        guard let uuid = UUID(uuidString: string) else {
            return nil
        }
        value = uuid
    }

    public func getPackedFDBTupleValue() -> Bytes {
        self._bytes.getPackedFDBTupleValue()
    }
}

extension FDB.ID: Codable where Value == Foundation.UUID {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let result = try container.decode(Data.self)

        self.init(UUID(uuid: try [UInt8](result).cast(error: FDB.Error.unexpectedError)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let bytes = getBytes(value)
        try container.encode(Data(bytes))
    }
}
