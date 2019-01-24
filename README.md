# FDBSwift <img src="https://img.shields.io/badge/Swift-4.2-brightgreen.svg" alt="Swift: 4.2" /> <img src="https://travis-ci.org/kirilltitov/FDBSwift.svg?branch=master" />
> **Fine. I'll do it myself.**
>> _It should definitely be better than Python bindings in Swift :D_

This is FoundationDB wrapper for Swift. It's quite low-level, (almost) `Foundation`less and can into Swift-NIO.

## Installation

Obviously, you need to install `FoundationDB` first. Download it from [official website](https://www.foundationdb.org/download/). Next part is tricky because subpackage [CFDBSwift](https://github.com/kirilltitov/CFDBSwift) (C bindings) won't link `libfdb_c` library on its own, and FoundationDB doesn't yet ship `pkg-config` during installation. Therefore you must install it yourself. Run
```bash
chmod +x ./scripts/install_pkgconfig.sh
./scripts/install_pkgconfig.sh
```
or copy `scripts/libfdb.pc` (choose your platform) to `/usr/local/lib/pkgconfig/` on macOS or `/usr/lib/pkgconfig/libfdb.pc` on Linux.

## Usage

### Root concepts

By default (and in the very core) this wrapper, as well as C API, operates with byte keys and values (not pointers, but `Array<UInt8>`). See [Keys, tuples and subspaces](#keys-tuples-and-subspaces) section for more details.

Values are always bytes (`typealias Bytes = [UInt8]`) (or `nil` if key not found). Why not `Data` you may ask? I'd like to stay `Foundation`less for as long as I can (srsly, import half of the world just for `Data` object which is a fancy wrapper around `NSData` which is a fancy wrapper around `[UInt8]`?) (Hast thou forgot that you need to wrap all your `Data` objects with `autoreleasepool` or otherwise you get _fancy_ memory leaks?) (except for Linux tho, yes), you can always convert bytes to `Data` with `Data(bytes: myBytes)` initializer (why would you want to do that? oh yeah, right, JSON... ok, but do it yourself plz, extensions to the rescue).

Ahem. Where was I? OK so about library API. First let's deal with synchronous API (there is also asynchronous, using Swift-NIO, see below).

### Connection

```swift
// Default cluster path depending on your OS
let fdb = FDB()
// OR
let fdb = FDB(cluster: "/usr/local/etc/foundationdb/fdb.cluster")
```
Optionally you may pass network stop timeout, API version and `DispatchQueue` to FDB initializer (as FDB always needs a dedicated thread to run its stuff).

Keep in mind that at this point connection has not yet been established, it automatically established on first actual database operation. If you would like to explicitly connect to database and catch possible errors, you should just call:
```swift
try fdb.connect()
```
Disconnection is automatic, on `deinit`. But also you may call `disconnect()` method directly. Be warned that if anything goes wrong during disconnection, you will get uncatchable fatal error. It's not that bad because disconnection should happen only once, when your application shuts down (and you shouldn't really care about fatal errors at that point). Also you _very_ should ensure that FDB really disconnected before actual shutdown (trap `SIGTERM` signal and wait for `disconnect` to finish), otherwise you might experience undefined behaviour (I personally haven't really encountered that yet, but it's not phantom menace; when you don't follow FoundationDB recommendations, things get quite messy indeed).

### Keys, tuples and subspaces

All keys are `FDBKey` which is a protocol:
```swift
public protocol FDBKey {
    func asFDBKey() -> Bytes
}
```
This protocol is adopted by `String`, `StaticString`, `Tuple`, `Subspace` and `Bytes` (aka `Array<UInt8>`), so you may freely use any of these types, or adopt this protocol in your custom types.

Since you would probably like to have some kind of namespacing in your application, you should stick to `Subspace` which is an extremely useful instrument for creating namespaces. Under the hood it utilizes the Tuple concept. You oughtn't really bother delving into it, just remember that currently subspaces accept `String`, `Int`, `Tuple` (hence `TuplePackable`), `nil` (why would you do that?) and `Bytes` as arguments.
```swift
// dump subspace if you would like to see how it looks from the inside
let rootSubspace = Subspace("root")
// also check Subspace.swift for more details and usecases
let childSubspace = rootSubspace.subspace("child", "subspace")
// OR
let childSubspace = rootSubspace["child"]["subspace"]
// OR
let childSubspace = rootSubspace["child", "subspace"]

// Talking about tuples:
let tuple = Tuple(Bytes([0, 1, 2]), 322, -322, nil, "foo", Tuple("bar", 1337, "baz"), Tuple(), nil)
let packed: Bytes = tuple.pack()
let unpacked: Tuple = Tuple(from: packed)
let tupleBytes: Bytes? = unpacked.tuple[0]
let tupleInt: Int? = unpacked.tuple[1]
// ...
let tupleEmptyTuple: Tuple? = unpacked.tuple[6]
let tupleNil: TuplePackable? = unpacked.tuple[7]
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
try fdb.set(key: Tuple("foo", nil, "bar", Tuple("baz", "sas"), "lul"), value: someBytes)
// OR
try fdb.set(key: Subspace("foo").subspace("bar"), value: someBytes)
```

### Getting values

Value is always `Bytes?` (`nil` if key not found), you should unwrap it before use. Keys are, of course, still `FDBKey`s.
```swift
let value = try fdb.get(key: "someKey")
```

### Range get (multi get)

Since FoundationDB keys are lexicographically ordered over the underlying bytes, you can get all subspace values (or even from whole DB) by querying range from key `somekey\x00` to key `somekey\xFF` (from byte 0 to byte 255). You shouldn't do it manually though, as `Subspace` object has a shortcut that does it for you.

Additionally, `get(range:)` (and its versions) method returns not `Bytes`, but special structure `KeyValuesResult` which holds an array of `KeyValue` structures and a flag indicating whether DB can provide more results (pagination, kinda):
```swift
public struct KeyValue {
    public let key: Bytes
    public let value: Bytes
}

public struct KeyValuesResult {
    public let records: [KeyValue]
    public let hasMore: Bool
}
```

If range call returned zero records, it would result in an empty `KeyValuesResult` struct (not `nil`).
```swift
let subspace = Subspace("root")
let range = subspace.range
/*
  these three calls are completely equal (can't really come up with case when you need second form,
  but whatever, I've seen worse whims)
*/
let result: KeyValuesResult = try fdb.get(range: range)
let result: KeyValuesResult = try fdb.get(begin: range.begin, end: range.end)
let result: KeyValuesResult = try fdb.get(subspace: subspace)

// though call below is not equal to above one because `key(subspace:)` overload implicitly loads range
// this one will load bare subspace key
let result: KeyValuesResult = try fdb.get(key: subspace)

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
try fdb.clear(key: rootSubspace["child", nil, Tuple("foo", "bar"), "concrete_record"])

// clears whole subspace, including "concrete_record" key
try fdb.clear(range: childSubspace.range)
```

Don't forget that actual clearing is not performed until transaction commit.

### Atomic operations

FoundationDB also supports atomic operations like ADD, AND, OR, XOR and stuff like that (please refer to [docs](https://apple.github.io/foundationdb/api-c.html#c.FDBMutationType)). You can perform any of these operations with `atomic(op:key:value:)` method:
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

### Asynchronous API

If your application is NIO-based (pure [Swift-NIO](https://github.com/apple/swift-nio) or [Vapor](http://vapor.codes)), you would definitely want (_need_) to utilize `EventLoopFuture`s, otherwise you are in a great danger of deadlocks which are exceptionally tricky to debug (I've once spent whole weekend debugging my first deadlock, don't repeat my mistakes; thin ice, big time).

If you would like to know Swift-NIO Futures better, please refer to [docs](https://apple.github.io/swift-nio/docs/current/NIO/Classes/EventLoopFuture.html).

In order to utilize Futures, you must first have a reference to current `EventLoop`. If you use Swift-NIO directly, it's available within `ChannelHandler.channelRead` method, as `ChannelHandlerContext`s argument property `eventLoop`. If you use Vapor (starting from version 3.0), it's available from `req` argument within each action. Please refer to [official docs](https://docs.vapor.codes/3.0/async/overview/#event-loop).

All asynchronous stuff (basically mirror methods for all synchronous methods, see [`Transaction+Sync.swift`](https://github.com/kirilltitov/FDBSwift/blob/master/Sources/FDB/Transaction/Transaction%2BSync.swift)) is located in Transaction class (see [`Transaction+NIO.Swift`](https://github.com/kirilltitov/FDBSwift/blob/master/Sources/FDB/Transaction/Transaction%2BNIO.swift) file for complete API), but it all starts with creating a new transaction with `EventLoop`:
```swift
let transactionFuture: EventLoopFuture<Transaction> = fdb.begin(eventLoop: currentEventLoop)
```

Transaction here is wrapped with an `EventLoopFuture` because this call can fail (no connection, something is wrong, etc.).

This transaction now supports asynchronous methods (if you try to call asynchronous method on transaction created without `EventLoop`, you will instantly get failed `EventLoopPromise`, so take care). Keep in mind that almost all async transaction methods returns not just `EventLoopFuture` with result (or `Void`) inside, but a tuple of result and this very same transaction, because if you'd like to commit it yourself, you must have a reference to it, and it's your job to pass this transaction further while you need it.

Complete example:

```swift
// EmbeddedEventLoop is meant to be used for testing only
let key = Subspace("1337")["322"]
let future: EventLoopFuture<String> = fdb
    .begin(eventLoop: currentEventLoop)
    .then { transaction in
        transaction.set(key: key, value: Bytes([1, 2, 3]))
    }
    .then { transaction in
        transaction.get(key: key)
    }
    .thenThrowing { (bytes, transaction) in
        guard let bytes = bytes else {
            throw MyApplicationError.Something("Bytes are not bytes")
        }
        guard let string = String(bytes: bytes, encoding: .ascii) else {
            throw MyApplicationError.Something("String is not string")
        }
        let _: EventLoopFuture<Void> = transaction.commit()
        return string
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
fdb.verbose = true
```

## Troubleshooting

**Q**: I cannot compile my project, something like `"Undefined symbols for architecture"` and tons of similar crap. Pls halp.

**A**: You haven't properly installed `pkg-config` for FoundationDB, see [Installation section](#installation).

**Q**: I'm getting strange error on second operation: `"API version already set"`. What's happening?

**A**: You tried to create more than one instance of FDB object, which is a) prohibited b) not needed at all since one instance is just enough for any application (if not, consider horizontal scaling, FDB absolutely shouldn't be a bottleneck of your application). Philosophically speaking it's not very ok, there should be a way of creating more than one of FDB connection in a runtime, and I will definitely try to make it possible. Still, I don't think that FDB connection pooling is a good idea, it already does everything for you.

**Q**: My application/server just stuck, it stopped responding and dispatching requests. The heck?

**A**: It's called deadlock. You blocked main/event loop thread. You never block main thread (or event loop thread). It happened because you did some blocking disk or network operation within `then`/`map` future closure (probably, while requesting the very same application instance over network). Do your blocking (IO/network) operation within `DispatchQueue.async` context, resolve it with `EventLoopPromise` and return future result as `EventLoopFuture`.

## Warnings

This package is on ~extremely~ ~very~ ~quite~ moderately early stage. Though I did some CRUD-tests (including highload tests) on my machine (macOS) and got all tests passing on Ubuntu, I would recommend to use it in production with caution. Obviously, I am not responsible for sudden shark attacks and your data corruption.

Additionally, I don't guarantee tuples/subspaces compatibility with other languages implementations. During development I refered to Python implementation, but there might be slight differences (like unicode string and byte string packing, see [design doc](https://github.com/apple/foundationdb/blob/master/design/tuple.md) on strings and [my comments](https://github.com/kirilltitov/FDBSwift/blob/master/Tests/FDBTests/TupleTests.swift) on that). Probably one day I'll spend some time on ensuring packing compatibility, but that's not high priority for me. Personal opinion: you shouldn't mix DB clients at all, really. You have some architectural issues if you want things like that.

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
* Even more verbose
* Transaction options
* More sugar for atomic operations
* Network options
* Directories
* The rest of C API
* The rest of tuple pack/unpack (only floats, I think?)
* Docblocks and built-in documentation
* Drop VR support
