import FDB
import CFDB
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

extension Array where Element == Byte {
    var string: String {
        return String(bytes: self, encoding: .ascii)!
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
    let fdb = FDB()
    let key = "lul"
    var keyBytes = [UInt8](key.utf8)
    let keyBytesLength = Int32(keyBytes.count)

    typealias Bytes = [UInt8]

    func getRandomBytes() -> Bytes {
        var bytes = Bytes()
        for _ in 0..<10 {
            bytes.append(UInt8.random(in: 0..<UInt8.max))
        }
        return bytes
    }

//    print("etalon")
//    print(bytes)

    let connectProfiler = Profiler.begin()
    do {
        try fdb.connect()
    } catch {
        dump(error)
    }
    print("Connected: \(connectProfiler.end().rounded(toPlaces: 5))s")

    do {
//        try fdb.set(key: "lull", value: "sas".bytes)
        let transaction = try fdb.begin()
//        let tuple = Tuple("foo", "bar", nil, Tuple(), "sas")
//        let tupleKey = tuple.pack()
//        try fdb.set(key: tupleKey, value: bytes)
//        dump(tupleKey.string)
//        dump(try fdb.get(key: tupleKey)?.string)
        //try transaction.set(key: "lull".bytes, value: "sas".bytes)
//        dump(try transaction.get(key: "lull".bytes)?.string)
//        let value = try fdb.get(
//            begin: "k".bytes,
//            end: "m".bytes
//        )
//        value.forEach {
//            dump("\($0.key.string) - \($0.value.string)")
//            return
//        }
//        try transaction.commit()
        let subspace1 = Subspace("parent")
        let subspace2 = subspace1["child", "subchild2"]
//        try fdb.clear(range: subspace2.range)
        for i in 0..<2 {
            try fdb.set(key: subspace2["key \(i)"], value: getRandomBytes())
        }
        try fdb.get(subspace: subspace2).forEach {
            dump("\($0.key.string) - \($0.value.string)")
            return
        }
        exit(0)
        for i in 0...10 {
//            let writeProfiler = Profiler.begin()
            try transaction.set(key: subspace2["teonoman #\(i)"], value: getRandomBytes())

            //try fdb.clear(range: subspace2.range)
//            let writeTime = writeProfiler.end().rounded(toPlaces: 5)
//            let readProfiler = Profiler.begin()
            //let _ = try transaction.get(key: keyBytes)
            //try transaction.clear(key: keyBytes)
//            fdb_transaction_clear(transaction.pointer, "lul", 3)
//            dump(value)
//            let readTime = readProfiler.end().rounded(toPlaces: 5)
//            print("Iteration #\(i), w: \(writeTime), r: \(readTime)")
//            print("Iteration #\(i)")
        }
        try transaction.commit()
//        sleep(60)
    } catch {
        dump(error)
    }
}

main()

print("Goodbye")
