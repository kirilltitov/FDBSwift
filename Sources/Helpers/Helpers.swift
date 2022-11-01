import Dispatch
import Foundation

public typealias Byte = UInt8
public typealias Bytes = [Byte]

public extension String {
    @inlinable
    var bytes: Bytes {
        Bytes(self.utf8)
    }

    @inlinable
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

public extension Bytes {
    @inlinable
    func cast<R>(error: (String) -> Error) throws -> R {
        guard MemoryLayout<R>.size == self.count else {
            throw error(
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

    @inlinable
    var length: Int32 {
        numericCast(self.count)
    }

    @inlinable
    var string: String {
        String(bytes: self, encoding: .ascii)!
    }
}


/// Returns little-endian binary representation of arbitrary value
@inlinable
public func getBytes<Input>(_ input: Input) -> Bytes {
    withUnsafeBytes(of: input) { Bytes($0) }
}

/// Returns little-endian binary representation of arbitrary value
@inlinable
public func getBytes(_ input: String) -> Bytes {
    Bytes(input.utf8)
}

/// Returns big-endian IEEE binary representation of a floating point number
@inlinable
public func getBytes(_ input: Float32) -> Bytes {
    getBytes(input.bitPattern.bigEndian)
}

/// Returns big-endian IEEE binary representation of a double number
@inlinable
public func getBytes(_ input: Double) -> Bytes {
    getBytes(input.bitPattern.bigEndian)
}

// taken from Swift-NIO
@inlinable
public func debugOnly(_ body: () -> Void) {
    assert({ body(); return true }())
}

public extension UnsafePointer {
    @inlinable
    func unwrapPointee(count: Int32) -> [Pointee] {
        let items = Int(count)
        let buffer = self.withMemoryRebound(to: Pointee.self, capacity: items) {
            UnsafeBufferPointer(start: $0, count: items)
        }
        return Array(buffer)
    }
}

public extension UnsafePointer where Pointee == Byte {
    @inlinable
    func getBytes(count: Int32) -> Bytes {
        let items = Int(count) / MemoryLayout<Byte>.stride
        let buffer = self.withMemoryRebound(to: Byte.self, capacity: items) {
            UnsafeBufferPointer(start: $0, count: items)
        }
        return Array(buffer)
    }
}

public extension UnsafeRawPointer {
    // Boy this is unsafe :D
    @inlinable
    func getBytes(count: Int32) -> Bytes {
        self.assumingMemoryBound(to: Byte.self).getBytes(count: count)
    }
}

public extension DispatchSemaphore {
    func wait(for seconds: Int) -> DispatchTimeoutResult {
        self.wait(timeout: .now() + .seconds(seconds))
    }
}
