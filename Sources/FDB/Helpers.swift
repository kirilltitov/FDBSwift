import Dispatch
import CFDB

internal extension String {
    var bytes: Bytes {
        return Bytes(self.utf8)
    }
}

internal extension Bool {
    var int: fdb_bool_t {
        return self ? 1 : 0
    }
}

internal extension Array where Element == Byte {
    func cast<R>() -> R {
        precondition(
            MemoryLayout<R>.size == self.count,
            "Memory layout size for result type '\(R.self)' (\(MemoryLayout<R>.size) bytes) does not match with given byte array length (\(self.count) bytes)"
        )
        return self.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: R.self).pointee
        }
    }

    var length: Int32 {
        return Int32(self.count)
    }
}

// little endian byte order
internal func getBytes<Input>(_ input: Input) -> Bytes {
    return withUnsafeBytes(of: input) { Bytes($0) }
}

internal extension UnsafePointer {
    func unwrapPointee(count: Int32) -> [Pointee] {
        let items = Int(count)
        let buffer = self.withMemoryRebound(to: Pointee.self, capacity: items) {
            UnsafeBufferPointer(start: $0, count: items)
        }
        return Array(buffer)
    }
}

internal extension UnsafePointer where Pointee == Byte {
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
    func getBytes(count: Int32) -> Bytes {
        return self.assumingMemoryBound(to: Byte.self).getBytes(count: count)
    }
}

internal extension DispatchSemaphore {
    /// Blocks current thread until semaphore is released or timeout of given seconds is exceed
    ///
    /// - Parameters:
    ///   - for: Seconds to wait before unblocking
    /// - Returns: Wait result. Can be `.success` if semaphore succesfully released or `.timedOut` if else
    func wait(for seconds: Int) -> DispatchTimeoutResult {
        return self.wait(timeout: .secondsFromNow(seconds))
    }
}

internal extension DispatchTime {
    static func seconds(_ seconds: Int) -> DispatchTime {
        return self.init(uptimeNanoseconds: UInt64(seconds) * 1_000_000_000)
    }

    static func secondsFromNow(_ seconds: Int) -> DispatchTime {
        return self.init(secondsFromNow: seconds)
    }

    init(secondsFromNow seconds: Int) {
        self.init(uptimeNanoseconds: DispatchTime.now().rawValue + DispatchTime.seconds(seconds).rawValue)
    }
}
