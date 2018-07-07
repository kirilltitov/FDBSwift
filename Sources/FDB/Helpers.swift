import Dispatch
import CFDB

internal extension String {
    var bytes: Bytes {
        return Bytes(self.utf8)
    }
}

internal extension OpaquePointer {
    func asFuture() -> Future {
        return Future(self)
    }

    @discardableResult func waitForFuture() throws -> Future {
        return try self.asFuture().waitAndCheck()
    }
}

internal extension UnsafePointer where Pointee == Byte {
    func getBytes(length: Int32) -> Bytes {
        let numItems = Int(length) / MemoryLayout<Byte>.stride
        let buffer = self.withMemoryRebound(to: Byte.self, capacity: numItems) {
            UnsafeBufferPointer(start: $0, count: numItems)
        }
        return Array(buffer)
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
