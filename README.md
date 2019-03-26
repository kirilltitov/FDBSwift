# FDBSwift v3 <img src="https://img.shields.io/badge/Swift-4.2-brightgreen.svg" alt="Swift: 4.2" /> <img src="https://img.shields.io/badge/Swift-5.0-green.svg" alt="Swift: 5.0" /> <img src="https://travis-ci.org/kirilltitov/FDBSwift.svg?branch=master" />
> **Fine. I'll do it myself.**
>> _Episode III: Revenge of FoundationDB_

This is FoundationDB client for Swift. It's quite low-level, (almost) `Foundation`less and can into Swift-NIO.

## Installation

Obviously, you need to install `FoundationDB` first. Download it from [official website](https://www.foundationdb.org/download/). Next part is tricky because subpackage [CFDBSwift](https://github.com/kirilltitov/CFDBSwift) (C bindings) won't link `libfdb_c` library on its own, and FoundationDB doesn't yet ship `pkg-config` during installation. Therefore you must install it yourself. Run
```bash
chmod +x ./scripts/install_pkgconfig.sh
./scripts/install_pkgconfig.sh
```
or copy `scripts/libfdb.pc` (choose your platform) to `/usr/local/lib/pkgconfig/` on macOS or `/usr/lib/pkgconfig/libfdb.pc` on Linux.

## Migration to v3

Since v3 is a major version, it reshapes the whole FDBSwift public API reducing it to three (and a half) global names:
* `FDB` — this is where all stuff lays now.
* `AnyFDBKey` — a type-erased FDB key value.
* `FDBTuplePackable` — a type-erased Tuple value.
* (it's the half) `Byte` and `Bytes` (just typealiases for `UInt8` and `[UInt8]`), and should probably be defined as a part of Swift Foundation.

Given the above, you should migrate all your v2 and v1 code to new names. You can simplify this process by using this shim which will help you with migration to v3:

```swift
@available(*, deprecated, renamed: "FDB.Transaction")
public typealias Transaction = FDB.Transaction
@available(*, deprecated, renamed: "FDB.Tuple")
public typealias Tuple = FDB.Tuple
@available(*, deprecated, renamed: "FDB.Subspace")
public typealias Subspace = FDB.Subspace
@available(*, deprecated, renamed: "FDBTuplePackable")
public typealias TuplePackable = FDBTuplePackable
@available(*, deprecated, renamed: "AnyFDBKey")
public typealias FDBKey = AnyFDBKey
public extension FDB {
    @available(*, deprecated, renamed: "begin(on:)")
    public func begin(eventLoop: EventLoop) -> EventLoopFuture<FDB.Transaction> {
        return self.begin(on: eventLoop)
    }
}
```

Just place it in `main.swift` or somewhere else, and you will able to track down all deprecated FDB names usages.

**Q**: Why haven't you committed this shim to repository?

**A**: I don't like littering the global namespace, and I don't want to wait two more major versions until I'm able to actually delete these definitions (one version to deprecate, and another to delete for good).

Note: I don't really like leaving `AnyFDBKey` and `FDBTuplePackable` in the global namespace, I'd love to hide them all under the `FDB` name as well. However, Swift _currently_ doesn't allow to define nested protocols, which is a shame. But worry not, the day Swift allows to do that, I will release a respective update :)

## Usage

### Root concepts

By default (and in the very core) this wrapper, as well as C API, operates with byte keys and values (not pointers, but `Array<UInt8>`). See [Keys, tuples and subspaces](#keys-tuples-and-subspaces) section for more details.

Values are always bytes (`typealias Bytes = [UInt8]`) (or `nil` if key not found). Why not `Data` you may ask? I'd like to stay `Foundation`less for as long as I can (srsly, import half of the world just for `Data` object which is a fancy wrapper around `NSData` which is a fancy wrapper around `[UInt8]`?) (Hast thou forgot that you need to wrap all your `Data` objects with `autoreleasepool` or otherwise you get _fancy_ memory leaks?) (except for Linux tho, yes), you can always convert bytes to `Data` with `Data(bytes: myBytes)` initializer (why would you want to do that? oh yeah, right, JSON... ok, but do it yourself plz, extensions to the rescue).

Ahem. Where was I? OK so about library API. First let's deal with synchronous API (there is also asynchronous, using Swift-NIO, see below).

### Connection

```swift
// Default cluster file path depending on your OS
let fdb = FDB()
// OR
let fdb = FDB(clusterFile: "/usr/local/etc/foundationdb/fdb.cluster")
```
Optionally you may pass network stop timeout.

Keep in mind that at this point connection has not yet been established, it's automatically established on first actual database operation. If you would like to explicitly connect to database and catch possible errors, you should just call:
```swift
try fdb.connect()
```
Disconnection is automatic, on `deinit`. But you may also call `disconnect()` method directly. Be warned that if anything goes wrong during disconnection, you will get uncatchable fatal error. It's not that bad because disconnection should happen only once, when your application shuts down (and you shouldn't really care about fatal errors at that point). Also you _very_ ought to ensure that FDB really disconnected before actual shutdown (trap `SIGTERM` signal and wait for `disconnect` to finish), otherwise you might experience undefined behaviour (I personally haven't really encountered that yet, but it's not phantom menace; when you don't follow FoundationDB recommendations, things get quite messy indeed).

Before you connected to FDB cluster you may set network options:

```swift
try fdb.setOption(.TLSCertPath(path: "/opt/fdb/tls/chain.pem"))
try fdb.setOption(.TLSPassword(password: "changeme"))
try fdb.setOption(.buggifyEnable)
```

See [`FDB+NetworkOptions.swift`](https://github.com/kirilltitov/FDBSwift/blob/master/Sources/FDB/FDB%2BNetworkOptions.swift) file for complete set of network options.

### Keys, tuples and subspaces

All keys are `AnyFDBKey` which is a protocol:
```swift
public protocol AnyFDBKey {
    func asFDBKey() -> Bytes
}
```
This protocol is adopted by `String`, `StaticString`, `Tuple`, `Subspace` and `Bytes` (aka `Array<UInt8>`), so you may freely use any of these types, or adopt this protocol in your custom types.

Since you would probably like to have some kind of namespacing in your application, you should stick to `Subspace` which is an extremely useful instrument for creating namespaces. Under the hood it utilizes the Tuple concept. You oughtn't really bother delving into it, just remember that currently subspaces accept `String`, `Int`, `Tuple` (hence `FDBTuplePackable`), `FDB.Null` (why would you do that?) and `Bytes` as arguments.
```swift
// dump subspace if you would like to see how it looks from the inside
let rootSubspace = FDB.Subspace("root")
// also check Subspace.swift for more details and usecases
let childSubspace = rootSubspace.subspace("child", "subspace")
// OR
let childSubspace = rootSubspace["child"]["subspace"]
// OR
let childSubspace = rootSubspace["child", "subspace"]

// Talking about tuples:
let tuple = FDB.Tuple(
    Bytes([0, 1, 2]),
    322,
    -322,
    FDB.Null(),
    "foo",
    FDB.Tuple("bar", 1337, "baz"),
    FDB.Tuple(),
    FDB.Null()
)
let packed: Bytes = tuple.pack()
let unpacked: FDB.Tuple = try FDB.Tuple(from: packed)
let tupleBytes: Bytes = unpacked.tuple[0]
let tupleInt: Int = unpacked.tuple[1]
// ...
let tupleEmptyTuple: FDB.Tuple = unpacked.tuple[6]
let tupleNull: FDBTuplePackable = unpacked.tuple[7]
if tupleNull is FDB.Null || unpacked.tuple[7] is FDB.Null {}
// you get the idea
```
**Alert!** Due to a bug in Linux Swift Foundation (4.0+) any strings in Linux are decoded from `Bytes` or `Data` as null-terminated, i.e. `String(bytes: [102, 111, 111, 0, 98, 97, 114], encoding: .ascii)` on macOS would be `foo\u{00}bar` (as expected), but on Linux it's just `foo`. Keep that in mind, avoid using nulls in your string tuples.

### Setting values

Simple as that:
```swift
try fdb.set(key: "somekey", value: someBytes)
// OR
try fdb.set(key: Bytes([0, 1, 2, 3]), value: someBytes)
// OR
try fdb.set(key: FDB.Tuple("foo", FDB.Null(), "bar", FDB.Tuple("baz", "sas"), "lul"), value: someBytes)
// OR
try fdb.set(key: Subspace("foo").subspace("bar"), value: someBytes)
```

### Getting values

Value is always `Bytes?` (`nil` if key not found), you should unwrap it before use. Keys are, of course, still `AnyFDBKey`s.
```swift
let value = try fdb.get(key: "someKey")
```

### Range get (multi get)

Since FoundationDB keys are lexicographically ordered over the underlying bytes, you can get all subspace values (or even from whole DB) by querying range from key `somekey\x00` to key `somekey\xFF` (from byte 0 to byte 255). You shouldn't do it manually though, as `Subspace` object has a shortcut that does it for you.

Additionally, `get(range:)` (and its versions) method returns not `Bytes`, but special structure `FDB.KeyValuesResult` which holds an array of `FDB.KeyValue` structures and a flag indicating whether DB can provide more results (pagination, kinda):
```swift
public extension FDB {
    /// A holder for key-value pair
    public struct KeyValue {
        public let key: Bytes
        public let value: Bytes
    }
    
    /// A holder for key-value pairs result returned from range get
    public struct KeyValuesResult {
        /// Records returned from range get
        public let records: [FDB.KeyValue]

        /// Indicates whether there are more results in FDB
        public let hasMore: Bool
    }
}
```

If range call returned zero records, it would result in an empty `FDB.KeyValuesResult` struct (not `nil`).
```swift
let subspace = FDB.Subspace("root")
let range = subspace.range
/*
  these three calls are completely equal (can't really come up with case when you need second form,
  but whatever, I've seen worse whims)
*/
let result: FDB.KeyValuesResult = try fdb.get(range: range)
let result: FDB.KeyValuesResult = try fdb.get(begin: range.begin, end: range.end)
let result: FDB.KeyValuesResult = try fdb.get(subspace: subspace)

// though call below is not equal to above one because `key(subspace:)` overload implicitly loads range
// this one will load bare subspace key
let result: FDB.KeyValuesResult = try fdb.get(key: subspace)

result.records.forEach {
    dump("\($0.key) - \($0.value)")
    return
}
```

### Clearing values

Clearing (removing, deleting, you name it) records is simple as well.
```swift
try fdb.clear(key: childSubspace.subspace("concrete_record"))
// OR
try fdb.clear(key: childSubspace["concrete_record"])
// OR
try fdb.clear(key: rootSubspace["child"]["subspace"]["concrete_record"])
// OR EVEN
try fdb.clear(key: rootSubspace["child", "subspace", "concrete_record"])
// OR EVEN (this is not OK, but still possible :)
try fdb.clear(key: rootSubspace["child", FDB.Null, FDB.Tuple("foo", "bar"), "concrete_record"])

// clears whole subspace, including "concrete_record" key
try fdb.clear(range: childSubspace.range)
```

Don't forget that actual clearing is not performed until transaction commit.

### Atomic operations

FoundationDB also supports atomic operations like `ADD`, `AND`, `OR`, `XOR` and stuff like that (please refer to [docs](https://apple.github.io/foundationdb/api-c.html#c.FDBMutationType)). You can perform any of these operations with `atomic(op:key:value:)` method:
```swift
try fdb.atomic(.Add, key: key, value: 1)
```

Knowing that most popular atomic operation is increment (or decrement), I added handy syntax sugar:
```swift
try fdb.increment(key: key)
// OR returning incremented value, which is always Int64
let result: Int64 = try fdb.increment(key: key)
// OR
let result = try fdb.increment(key: key, value: 2)
```

However, keep in mind that example above isn't atomic anymore.

And decrement, which is just a proxy for `increment(key:value:)`, just inverting the `value`:
```swift
let result = try fdb.decrement(key: key)
// OR
let result = try fdb.decrement(key: key, value: 2)
```

### Transactions

All previous examples are utilizing `FDB` object methods which are implicitly transactional. If you would like to perform more than one operation within one transaction (and experience all delights of [ACID](https://en.wikipedia.org/wiki/ACID_(computer_science))), you should first begin transaction using `begin()` method on `FDB` object context and then do your stuff (just don't forget to `commit()` it in the end, by default transactions roll back if not committed explicitly, or after timeout of 5 seconds):
```swift
let transaction = try fdb.begin()

// By default transactions are NOT committed, you must do it explicitly or pass optional arg `commit`
try transaction.set(key: "someKey", value: someBytes, commit: true)

try transaction.commit()
// OR
transaction.reset()
// OR
transaction.cancel()
// Or you can just leave transaction object in place and it resets & destroys itself on `deinit`.
// Consider it auto-rollback.
// Please refer to official docs on reset and cancel behaviour:
// https://apple.github.io/foundationdb/api-c.html#c.fdb_transaction_reset
```

It's not really necessary to commit readonly transaction though :)

Additionally you may set transaction options using `transaction.setOption(_:)` method:
```swift
let transaction: FDB.Transaction = ...
try transaction.setOption(.transactionLoggingEnable(identifier: "debuggable_transaction"))
try transaction.setOption(.snapshotRywDisable)
```

See [`Transaction+Options.swift`](https://github.com/kirilltitov/FDBSwift/blob/master/Sources/FDB/Transaction/Transaction%2BOptions.swift) file for complete set of options.

### Asynchronous API

If your application is NIO-based (pure [Swift-NIO](https://github.com/apple/swift-nio) or [Vapor](http://vapor.codes)), you would definitely want (_need_) to utilize `EventLoopFuture`s, otherwise you are in a great danger of deadlocks which are exceptionally tricky to debug (I've once spent whole weekend debugging my first deadlock, don't repeat my mistakes; thin ice, big time).

If you would like to know Swift-NIO Futures better, please refer to [docs](https://apple.github.io/swift-nio/docs/current/NIO/Classes/EventLoopFuture.html).

In order to utilize Futures, you must first have a reference to current `EventLoop`. If you use Swift-NIO directly, it's available within `ChannelHandler.channelRead` method, as `ChannelHandlerContext`s argument property `eventLoop`. If you use Vapor (starting from version 3.0), it's available from `req` argument within each action. Please refer to [official docs](https://docs.vapor.codes/3.0/async/overview/#event-loop).

All asynchronous stuff (basically mirror methods for all synchronous methods, see [`Transaction+Sync.swift`](https://github.com/kirilltitov/FDBSwift/blob/master/Sources/FDB/Transaction/Transaction%2BSync.swift)) is located in Transaction class (see [`Transaction+NIO.Swift`](https://github.com/kirilltitov/FDBSwift/blob/master/Sources/FDB/Transaction/Transaction%2BNIO.swift) file for complete API), but it all starts with creating a new transaction with `EventLoop`:
```swift
let transactionFuture: EventLoopFuture<Transaction> = fdb.begin(eventLoop: currentEventLoop)
```

Transaction here is wrapped with an `EventLoopFuture` because this call may fail (no connection, something is wrong, etc.).

This transaction now supports asynchronous methods (if you try to call asynchronous method on transaction created without `EventLoop`, you will instantly get failed `EventLoopPromise`, so take care). Keep in mind that almost all async transaction methods returns not just `EventLoopFuture` with result (or `Void`) inside, but a tuple of result and this very same transaction, because if you'd like to commit it yourself, you must have a reference to it, and it's your job to pass this transaction further while you need it.

### Conflicts, retries and `withTransaction`

Since FoundationDB is _quite_ a transactional database, sometimes `commit`s might not succeed due to serialization failures. This can happen when two or more transactions create overlapping conflict ranges. Or, simply speaking, when they try to access or modify same keys (unless they are not in `snapshot` read mode) at the same time. This is expected (and, in a way, welcomed) behaviour because this is how ACID is achieved.

In these [not-so-rare] cases transaction is allowed to be replayed again. How do you know if transaction can be replayed? It's failed with a special `FDB.Error` case `.transactionRetry(FDB.Transaction)` which holds current transaction as an associated value. If your transaction (or its respective `EventLoopFuture`) is failed with this particular error, it means that the transaction has already been rolled back to its initial state and is ready to be executed again.

You can implement this retry logic manually or you can just use builtin `FDB` object function `withTransaction`. This function, as always, comes with two flavors: synchronous and NIO:

```swift
let maybeString: String? = try fdb.withTransaction { transaction in
    guard let bytes: Bytes = try transaction.get(key: key) else {
        return nil
    }
    try transaction.commitSync()
    return String(bytes: bytes, encoding: .ascii)
}

// OR

let maybeStringFuture: EventLoopFuture<String?> = fdb.withTransaction(on: myEventLoop) { transaction in
    return transaction.get(key: key, commit: true)
        .map { maybeBytes, transaction in
            guard let bytes = maybeBytes else {
                return nil
            }
            return String(bytes: bytes, encoding: .ascii)
        }
}
```

Thus your block of code will be gently retried until transaction is successfully committed.

### Complete example

```swift
let key = FDB.Subspace("1337")["322"]

let future: EventLoopFuture<String> = fdb.withTransaction(on: myEventLoop) { transaction in
    return transaction
        .setOption(.timeout(milliseconds: 5000))
        .flatMap { transaction in
            transaction.setOption(.snapshotRywEnable)
        }
        .flatMap { transaction in
            transaction.set(key: key, value: Bytes([1, 2, 3]))
        }
        .flatMap { transaction in
            transaction.get(key: key, snapshot: true)
        }
        .flatMapThrowing { (maybeBytes, transaction) -> (String, FDB.Transaction) in
            guard let bytes = maybeBytes else {
                throw MyApplicationError.Something("Bytes are not bytes")
            }
            guard let string = String(bytes: bytes, encoding: .ascii) else {
                throw MyApplicationError.Something("String is not string")
            }
            return (string, transaction)
        }
        .flatMap { string, transaction in
            transaction
                .commit()
                .map { _ in string }
    }
}

future.whenSuccess { (resultString: String) in
    print("My string is '\(resultString)'")
}
future.whenFailure { (error: Error) in
    print("Error :C '\(error)'")
}

// OR (you only use wait method outside of main thread or eventLoop thread, because it's blocking)
let string: String = try future.wait()
```

Of course, in most cases it's much easier and cleaner to just pass `commit: true` argument into `set(key:value:commit:)` method (or its siblings), and it will do things for you.

### Debugging

If FDB doesn't kickstart properly and you're unsure on what's happening, you may enable verbose mode which prints useful debug info to `stdout`:
```swift
FDB.verbose = true
```

## Troubleshooting

**Q**: I cannot compile my project, something like `"Undefined symbols for architecture"` and tons of similar crap. Pls halp.

**A**: You haven't properly installed `pkg-config` for FoundationDB, see [Installation section](#installation).

**Q**: I'm getting strange error on second operation: `"API version already set"`. What's happening?

**A**: You tried to create more than one instance of FDB object, which is a) prohibited b) not needed at all since one instance is just enough for any application (if not, consider horizontal scaling, FDB absolutely shouldn't be a bottleneck of your application). Philosophically speaking it's not very ok, there should be a way of creating more than one of FDB connection in a runtime, and I will definitely try to make it possible. Still, I don't think that FDB connection pooling is a good idea, it already does everything for you.

**Q**: My application/server just stuck, it stopped responding and dispatching requests. The heck?

**A**: It's called deadlock. You blocked main/event loop thread. You never block main thread (or event loop thread). It happened because you did some blocking disk or network operation within `flatMap`/`map` future closure (probably, while requesting the very same application instance over network). Do your blocking (IO/network) operation within `DispatchQueue.async` context, resolve it with `EventLoopPromise` and return future result as `EventLoopFuture`.

## Warnings

Though I aim for full interlanguage compatibility of Tuple layer, I don't guarantee it. During development I refered to Python implementation, but there might be slight differences (like unicode string and byte string packing, see [design doc](https://github.com/apple/foundationdb/blob/master/design/tuple.md) on strings and [my comments](https://github.com/kirilltitov/FDBSwift/blob/master/Tests/FDBTests/TupleTests.swift) on that). In general it's should be quite compatible already. Probably one day I'll spend some time on ensuring packing compatibility, but that's not high priority for me.

## TODOs

* Enterprise support, vendor WSDL, rewrite on ~Java~ ~Scala~ ~Kotlin~ Java 10
* Drop enterprise support, rewrite on golang using react-native (pretty sure it will be a thing by that time)
* Blockchain? ICO? VR? AR?
* Rehab
* ✅ Proper errors
* ✅ Transactions rollback
* ✅ Tuples
* ✅ Tuples pack
* ✅ Tuples unpack
* ✅ Integer tuples
* ✅ Ranges
* ✅ Subspaces
* ✅ Atomic operations
* ✅ Tests
* ✅ Properly test on Linux
* ✅ 🎉 Asynchronous methods (Swift-NIO)
* ✅ More verbose
* ✅ Even more verbose
* ✅ Transaction options
* ✅ Network options
* ✅ Docblocks and built-in documentation
* The rest of tuple pack/unpack (only floats, I think?)
* More sugar for atomic operations
* The rest of C API (watches?)
* Directories
* Drop VR support
