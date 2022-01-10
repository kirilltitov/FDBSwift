import CFDB
import Dispatch

public typealias Byte = UInt8
public typealias Bytes = [Byte]

internal extension String {
    @usableFromInline
    var bytes: Bytes {
        Bytes(self.utf8)
    }

    @usableFromInline
    var safe: String {
        self
            .unicodeScalars
            .lazy
            .map { scalar in
                scalar == "\n"
                    ? "\n"
                    : scalar.escaped(asASCII: true)
            }
            .joined(separator: "")
    }
}

internal extension Bool {
    @usableFromInline
    var int: fdb_bool_t {
        self ? 1 : 0
    }
}

internal extension Bytes {
    @usableFromInline
    func cast<R>() throws -> R {
        guard MemoryLayout<R>.size == self.count else {
            throw FDB.Error.unexpectedError(
                """
                    Memory layout size for result type '\(R.self)' (\(MemoryLayout<R>.size) bytes) does
                    not match with given byte array length (\(self.count) bytes)
                """
            )
        }
        return self.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: R.self).pointee
        }
    }

    @usableFromInline
    var length: Int32 {
        numericCast(self.count)
    }

    @usableFromInline
    var string: String {
        String(bytes: self, encoding: .ascii)!
    }
}

/// Returns little-endian binary representation of arbitrary value
@usableFromInline
internal func getBytes<Input>(_ input: Input) -> Bytes {
    withUnsafeBytes(of: input) { Bytes($0) }
}

/// Returns big-endian IEEE binary representation of a floating point number
@usableFromInline
internal func getBytes(_ input: Float32) -> Bytes {
    getBytes(input.bitPattern.bigEndian)
}

/// Returns big-endian IEEE binary representation of a double number
@usableFromInline
internal func getBytes(_ input: Double) -> Bytes {
    getBytes(input.bitPattern.bigEndian)
}

// taken from Swift-NIO
@usableFromInline
internal func debugOnly(_ body: () -> Void) {
    assert({ body(); return true }())
}

internal extension UnsafePointer {
    @usableFromInline
    func unwrapPointee(count: Int32) -> [Pointee] {
        let items = Int(count)
        let buffer = self.withMemoryRebound(to: Pointee.self, capacity: items) {
            UnsafeBufferPointer(start: $0, count: items)
        }
        return Array(buffer)
    }
}

internal extension UnsafePointer where Pointee == Byte {
    @usableFromInline
    func getBytes(count: Int32) -> Bytes {
        let items = Int(count) / MemoryLayout<Byte>.stride
        let buffer = self.withMemoryRebound(to: Byte.self, capacity: items) {
            UnsafeBufferPointer(start: $0, count: items)
        }
        return Array(buffer)
    }
}

internal extension UnsafeRawPointer {
    // Boy this is unsafe :D
    @usableFromInline
    func getBytes(count: Int32) -> Bytes {
        self.assumingMemoryBound(to: Byte.self).getBytes(count: count)
    }
}

internal extension DispatchSemaphore {
    func wait(for seconds: Int) -> DispatchTimeoutResult {
        self.wait(timeout: .now() + .seconds(seconds))
    }
}
