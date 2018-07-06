import Dispatch
import FDB
import CFDB

public typealias FDBFuture = OpaquePointer
public typealias FDBTransaction = OpaquePointer
typealias Byte = UInt8
typealias Bytes = [Byte]

extension String {
    var bytes: Bytes {
        return Bytes(self.utf8)
    }

    var length: Int32 {
        return Int32(self.count)
    }
}

func checkError(_ errno: fdb_error_t) {
    guard errno == 0 else {
        print("FoundationDB error: \(String(cString: fdb_get_error(errno))) (code \(errno)")
        exit(errno)
    }
}

func waitAndCheckError(_ future: FDBFuture!) {
    checkError(fdb_future_block_until_ready(future))
    checkError(fdb_future_get_error(future))
}

func convert<T>(length: Int, data: UnsafePointer<UInt8>) -> [T] {
    let numItems = length / MemoryLayout<T>.stride
    let buffer = data.withMemoryRebound(to: T.self, capacity: numItems) {
        UnsafeBufferPointer(start: $0, count: numItems)
    }
    return Array(buffer)
}

let queue = DispatchQueue(label: "com.lgnkit.fdb", qos: .userInitiated, attributes: .concurrent)

let clusterPath = "/usr/local/etc/foundationdb/fdb.cluster"
checkError(fdb_select_api_version_impl(FDB_API_VERSION, FDB_API_VERSION))
print("FDB API version \(FDB_API_VERSION)")
checkError(fdb_setup_network())
queue.async {
    checkError(fdb_run_network())
}
print("Network initiated")

let clusterFuture = fdb_create_cluster(clusterPath)
waitAndCheckError(clusterFuture)
print("Got cluster");

var cluster: OpaquePointer!
checkError(fdb_future_get_cluster(clusterFuture, &cluster))
fdb_future_destroy(clusterFuture)

let DBName = "DB"
let DBFuture = fdb_cluster_create_database(cluster, DBName, Int32(DBName.count))
waitAndCheckError(DBFuture)
var db: OpaquePointer!
checkError(fdb_future_get_database(DBFuture, &db))
fdb_future_destroy(DBFuture)
print("Got database")

// write

var writeTransaction: OpaquePointer!
checkError(fdb_database_create_transaction(db, &writeTransaction))

let key = "foo"
let val = "bar"

fdb_transaction_set(
    writeTransaction,
    key.bytes,
    key.length,
    val.bytes,
    val.length
)

let commitFuture = fdb_transaction_commit(writeTransaction)
checkError(fdb_future_block_until_ready(commitFuture))
let commitError = fdb_future_get_error(commitFuture)
if commitError > 0 {
    waitAndCheckError(fdb_transaction_on_error(writeTransaction, commitError))
}
fdb_future_destroy(commitFuture)

print("Wrote value")

// read

var readTransaction: OpaquePointer!
checkError(fdb_database_create_transaction(db, &readTransaction))
let readFuture = fdb_transaction_get(readTransaction, key.bytes, key.length, 0)
waitAndCheckError(readFuture)

var readValPresent: Int32 = 0
var readVal: UnsafePointer<Byte>!
var readValLength: Int32 = 0
//var value:
checkError(fdb_future_get_value(
    readFuture,
    &readValPresent,
    &readVal,
    &readValLength
))

let readValBytes: Bytes = convert(length: Int(readValLength), data: readVal!)
dump(readValBytes)

print("Got value for '\(key)': '\(String(cString: readVal))' (length: \(String(describing: readValLength)))")
fdb_transaction_destroy(readTransaction)
fdb_future_destroy(readFuture)

checkError(fdb_stop_network())
print("Network stopped")
fdb_database_destroy(db)
print("Database resource destroyed")
fdb_cluster_destroy(cluster)
print("Cluster resource destroyed")

print("Goodbye")
