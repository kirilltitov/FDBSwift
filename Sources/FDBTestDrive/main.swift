import Foundation
import FDB
import NIO

extension Array where Element == Byte {
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

let etalon: [Int64] = (1...10).map { $0 }
var result = Array<Int64>()
result.reserveCapacity(etalon.count)

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let queue = DispatchQueue(label: "sync", qos: .userInitiated, attributes: .concurrent)
let semaphore = DispatchSemaphore(value: 1)

FDB.verbose = true
let fdb = FDB()
try fdb.connect()
let subspace = FDB.Subspace("atomic_load_test")
let key = subspace["id"]

//try fdb.clear(key: key)

let submitQueue = DispatchQueue(label: "ssdf", qos: .userInitiated, attributes: .concurrent)

for i in etalon {
//    submitQueue.async {
//        do {
//            result.append(try fdb.increment(key: key))
//        } catch {
//            dump(error)
//        }
        let future: EventLoopFuture<Void> = fdb
            .begin(on: group.next())
//            .then { transaction in
//                transaction.setOption(.retryLimit(retries: 20))
//            }
//            .then { transaction in
//                transaction.setOption(.maxRetryDelay(milliseconds: 3000))
//            }
            .then { (transaction: FDB.Transaction) in
                print("#\(i) Transaction started")
                return transaction.atomic(.add, key: key, value: Int64(1))
            }
            .then { (transaction: FDB.Transaction) in
                print("#\(i) Atomic add done")
                return transaction.get(key: key, commit: true)
            }
            .map { (bytes: Bytes?, transaction: FDB.Transaction) -> Void in
                print("#\(i) Got value")
                let value: Int64 = bytes!.cast()
                //queue.async(flags: .barrier) {
                    print("#\(i) Result \(value) set")
                    result.append(value)
                //}
                return
            }
        future.whenFailure { error in
            dump(error)
        }
//    }
}

print("Submitted all tasks")

sleep(3)

//dump(result)
//dump(result.sorted())

//semaphore.wait()
