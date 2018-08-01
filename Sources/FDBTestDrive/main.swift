import FDB
import Foundation

let fdb = FDB()

do {
    let key = "foo"
    let value = Bytes("?".utf8)
    print("key")
    print(key)
    print("value")
    print(value)
    try fdb.connect()
//    try fdb.set(key: key, value: Bytes("skdjfhsdkjf".utf8))
    let tr = try fdb.begin()

//    let bytes: Bytes? = try tr.get(key: key)
//    dump(String(bytes: bytes!, encoding: .ascii)!)
    //tr.set(key: key, value: value)
    try tr.commit().waitAndCheck()
    try tr.commit().waitAndCheck()
    //try fdb.clear(subspace: Subspace("fofofofofofo"))

//    let future: Future<Bytes?> = tr.get(key: key)
//    try future.whenReady { bytes in
//        dump("entered future")
//        dump(String(bytes: bytes!, encoding: .ascii)!)
//        dump("leaving future")
//    }
//    sleep(1)
    dump("bye")
} catch {
    print("ERROR")
    dump(error)
}
