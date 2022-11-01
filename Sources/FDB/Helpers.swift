import CFDB
import Dispatch
import Helpers

public typealias Byte = UInt8
public typealias Bytes = [Byte]

internal extension Bool {
    @usableFromInline
    var int: fdb_bool_t {
        self ? 1 : 0
    }
}
