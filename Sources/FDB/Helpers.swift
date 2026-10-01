import CFDB
import Dispatch

public typealias Byte = UInt8
public typealias Bytes = [Byte]

internal extension String {
    @usableFromInline
    var bytes: Bytes {
        Bytes(self.utf8)
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
            $0.loadUnaligned(as: R.self)
        }
    }

    @usableFromInline
    var length: Int32 {
        numericCast(self.count)
    }

    /// Lossy UTF-8 decoding of current bytes (invalid sequences are repaired, never traps)
    @usableFromInline
    var string: String {
        String(decoding: self, as: UTF8.self)
    }

    /// Printable representation of arbitrary bytes for logging purposes: printable ASCII is kept as is,
    /// everything else is rendered as `\xNN`. Never traps.
    @usableFromInline
    var printable: String {
        var result = ""
        result.reserveCapacity(self.count)
        for byte in self {
            if byte >= 0x20 && byte < 0x7F && byte != UInt8(ascii: "\\") {
                result.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                let hex = String(byte, radix: 16, uppercase: true)
                result += byte < 0x10 ? "\\x0\(hex)" : "\\x\(hex)"
            }
        }
        return result
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

internal extension UnsafePointer where Pointee == Byte {
    @usableFromInline
    func getBytes(count: Int32) -> Bytes {
        Array(UnsafeBufferPointer(start: self, count: Int(count)))
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
