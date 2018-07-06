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
        var i = 0
        while true {
            i += 1
            let writeProfiler = Profiler.begin()
            try fdb.set(key: key, value: bytes)
            let writeTime = writeProfiler.end().rounded(toPlaces: 5)
            let readProfiler = Profiler.begin()
            let _ = try fdb.get(key: key)
            let readTime = readProfiler.end().rounded(toPlaces: 5)
            print("Iteration #\(i), w: \(writeTime), r: \(readTime)")
        }
    } catch {
        dump(error)
    }
}

main()

print("Goodbye")
