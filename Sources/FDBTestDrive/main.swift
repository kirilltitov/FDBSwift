import FDB
import Foundation

public struct Profiler {
    internal var start: TimeInterval = Date().timeIntervalSince1970

    public static func begin() -> Profiler {
        return Profiler()
    }

    public func end() -> Float {
        var end = Date().timeIntervalSince1970
        end -= self.start
        return Float(end)
    }
}

extension Float {
    /// Rounds the double to decimal places value
    func rounded(toPlaces places:Int) -> Float {
        let divisor = pow(10.0, Float(places))
        return (self * divisor).rounded() / divisor
    }
}

func main() {
    let clusterPath = "/usr/local/etc/foundationdb/fdb.cluster"
    let fdb = FDB(cluster: clusterPath)
    let key = "lul"
    let keyBytes = [UInt8](key.utf8)

    typealias Bytes = [UInt8]
    var bytes = Bytes()
    for _ in 0..<UInt.random(in: 1..<50) {
        bytes.append(UInt8.random(in: 0..<UInt8.max))
    }

    print("etalon")
    print(bytes)

    let connectProfiler = Profiler.begin()
    do {
        try fdb.connect()
    } catch {
        dump(error)
    }
    print("Connected: \(connectProfiler.end().rounded(toPlaces: 5))s")

    do {
        let transaction = try fdb.begin()
        for i in 0...100000 {
//            let writeProfiler = Profiler.begin()
            try fdb.set(key: keyBytes, value: bytes, transaction: transaction, commit: false)
//            let writeTime = writeProfiler.end().rounded(toPlaces: 5)
//            let readProfiler = Profiler.begin()
//            try fdb.remove(key: key)
            let _ = try fdb.get(key: keyBytes, transaction: transaction, commit: false)
//            dump(value)
//            let readTime = readProfiler.end().rounded(toPlaces: 5)
//            print("Iteration #\(i), w: \(writeTime), r: \(readTime)")
            print("Iteration #\(i)")
        }
        try transaction.commit()
        sleep(60)
    } catch {
        dump(error)
    }
}

main()

print("Goodbye")
