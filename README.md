# FDBSwift v5 <img src="https://img.shields.io/badge/Swift-5.5-brightgreen.svg" alt="Swift: 5.5" />
> _Episode V: The Swift Awaitening_

This is FoundationDB client for Swift. It's quite low-level, (almost) `Foundation`less and can into `async`/`await`
(Swift-NIO not included and not required).

## ⚠️ **WARNING**: This is a release candidate which depends on upcoming Swift 5.5.1 (or so), macOS Monterey and God knows what else. For stable version, go to [v4 branch](https://github.com/kirilltitov/FDBSwift/tree/v4.2).

## Installation

Obviously, you need to install `FoundationDB` first. Download it from
[official website](https://www.foundationdb.org/download/). Next part is tricky because CFDB module (C bindings)
won't link `libfdb_c` library on its own, and FoundationDB doesn't yet ship `pkg-config` during installation.
Therefore you must install it yourself. Run

```bash
chmod +x ./scripts/install_pkgconfig.sh
./scripts/install_pkgconfig.sh
```

or copy `scripts/libfdb.pc` (choose your platform) to `/usr/local/lib/pkgconfig/` on macOS or
`/usr/lib/pkgconfig/libfdb.pc` on Linux.

## Migration from v4 to v5

v5 is a huge update in terms of internals and API. The most important update is `async`/`await` adoption, of course.
Because of that, Swift-NIO dependency has been dropped as redundant. Naturally, a lot of API just vanished as obsolete.
However, the remaining API looks pretty much the same, except it's not using event loops and futures.

In v4 (and earlier versions) there was a blocking API. Naturally, barely anyone used it because, well, why would you.
However, during v5 development it turned out that this API is a perfect foundation for adopting `async`/`await`,
just add `async` in signature and you're ready to go. Like it's been waiting for it really. It's a good thing I've been
maintaining this API along with NIO API. Good for me. 

So now there are only two ways of using FDBSwift:

1. Oneshot API with autocommit in `AnyFDB` (hence, `FDB`, the default impl), like `get(key:)`, `set(key:value:)`,
`atomic(_ op:key:value)` etc.
1. Transactional API which comes in two flavours:
    1. Manual transaction management with flat flow: `fdb.begin()`, some operations and `transaction.commit()`
    (basically you have full control over transaction and have to catch errors manually and process retry error yourself
    as well, see details and respective section below).
    1. Wrapped transactions: `fdb.withTransaction { transaction in /* some operations */ }` which manages retries
    for you, still you have to be aware of other errors.

One more not so minor change is that error case `FDB.Error.transactionRetry` doesn't have an `AnyFDBTransaction`
associated value anymore. It was handy in v4 when you could begin a NIO transaction and not have a reference to it
at ANY moment, including `flatMapError`/`recover` etc. (I personally had a lot of such cases).
Now this problem is gone for good and this associated value isn't needed at all.

## Usage

### Root concepts

By default (and in the very core) this wrapper, as well as C API, operates with byte keys and values (not pointers, but
`Array<UInt8>`). See [Keys, tuples and subspaces](#keys-tuples-and-subspaces) section for more details.

Values are always bytes (`typealias Bytes = [UInt8]`) (or `nil` if key not found). Why not `Data` you may ask? I'd like
to stay `Foundation`less for as long as I can (srsly, import half of the world just for `Data` object which is a fancy
wrapper around `NSData` which is a fancy wrapper around `[UInt8]`?) (Hast thou forgot that you need to wrap all your
`Data` objects with `autoreleasepool` or otherwise you get _fancy_ memory leaks?) (except for Linux tho, yes), you can
always convert bytes to `Data` with `Data(bytes: myBytes)` initializer (why would you want to do that? oh yeah, right,
JSON... ok, but do it yourself please, extensions to the rescue).

### Connection

```swift
// Default cluster file path depending on your OS
let fdb = FDB()

// OR
let fdb = FDB(clusterFile: "/usr/local/etc/foundationdb/fdb.cluster")
```

Optionally you may pass network stop timeout.

Keep in mind that at this point connection has not yet been established, it's automatically established on first actual
database operation. If you would like to explicitly connect to database and catch possible errors, just call:

```swift
try fdb.connect()
```

Disconnect is automatic, on `deinit`. But you may also call `disconnect()` method directly. Be warned that if
anything goes wrong during disconnect, you will get uncatchable fatal error. It's not that bad because disconnect
should happen only once, when your application shuts down (and you shouldn't really care about fatal errors at that
point). Also you _very_ ought to ensure that FDB really disconnected before actual shutdown (trap `SIGTERM` signal and
wait for `disconnect` to finish), otherwise you might experience undefined behaviour (I personally haven't really
encountered that yet, but it's not a phantom menace; when you don't follow FoundationDB recommendations things get
quite messy indeed).

Before you connected to FDB cluster you may also set network options:

```swift
try fdb.setOption(.TLSCertPath(path: "/opt/fdb/tls/chain.pem"))
try fdb.setOption(.TLSPassword(password: "changeme"))
try fdb.setOption(.buggifyEnable)
```

See [`FDB+NetworkOptions.swift`](Sources/FDB/FDB%2BNetworkOptions.swift) file for complete set of network options.

### Keys, tuples and subspaces

All keys are `AnyFDBKey` which is a protocol:

```swift
public protocol AnyFDBKey {
    func asFDBKey() -> Bytes
}
```

This protocol is adopted by `String`, `StaticString`, `Tuple` (NOT Tuple type from Swift), `Subspace` and `Bytes`
(aka `Array<UInt8>`), so you may freely use any of these types, or adopt this protocol in your custom types.

Since you would probably like to have some kind of key namespacing in your application, you should stick to `Subspace`
which is an extremely useful instrument for creating namespaces. Under the hood it utilizes the Tuple concept. You
oughtn't really bother delving into it (in short: basically a discount MsgPack, a tricky binary protocol), just remember
that currently subspaces accept `String`, `Int`, `Float` (aka `Float32`), `Double`, `Bool`, `UUID`, `Tuple`
(hence `FDBTuplePackable`), `FDB.Null` (why would you do that?) and `Bytes` as arguments.

```swift
// dump subspace if you would like to see how it looks from the inside
let rootSubspace = FDB.Subspace("root")

// also check Subspace.swift for more details and usecases
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
let tupleBytes: Bytes? = unpacked.tuple[0] as? Bytes
let tupleInt: Int? = unpacked.tuple[1] as? Int
// ...
let tupleEmptyTuple: FDB.Tuple? = unpacked.tuple[6] as? FDB.Tuple
let tupleNull: FDB.Null? = unpacked.tuple[7] as? FDB.Null
if tupleNull is FDB.Null || unpacked.tuple[7] is FDB.Null {}

// you get the idea
```

### Setting values

Simple as that:

```swift
try await fdb.set(key: "somekey", value: someBytes)

// OR
try await fdb.set(key: Bytes([0, 1, 2, 3]), value: someBytes)

// OR
try await fdb.set(key: FDB.Tuple("foo", FDB.Null(), "bar", FDB.Tuple("baz", "sas"), "lul"), value: someBytes)

// OR
try await fdb.set(key: Subspace("foo", "bar"), value: someBytes)
```

### Getting values

Value is always `Bytes?` (`nil` if key not found), you should unwrap it before use.
Keys are, of course, still `AnyFDBKey`s.

```swift
let value = try await fdb.get(key: "someKey")
```

### Range get (multi get)

Since in FoundationDB keys are lexicographically ordered over the underlying bytes, you can get all subspace values
(or even from whole DB) by querying range from key `somekey\x00` to key `somekey\xFF` (from byte 0 to byte 255).
You shouldn't do it manually though, as `Subspace` object has a shortcut that does it for you.

Additionally, `get(range:)` (and its versions) method returns not `Bytes`, but a special box structure
`FDB.KeyValuesResult` which holds an array of `FDB.KeyValue` structures and a flag indicating whether DB can provide
more results (pagination, kinda):

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
let result: FDB.KeyValuesResult = try await fdb.get(range: range)
let result: FDB.KeyValuesResult = try await fdb.get(begin: range.begin, end: range.end)
let result: FDB.KeyValuesResult = try await fdb.get(subspace: subspace)

// although call below is not equal to above one because `key(subspace:)` overload implicitly loads range
// this one will load bare subspace key
let result: FDB.KeyValuesResult = try await fdb.get(key: subspace)

result.records.forEach {
    dump("\($0.key) - \($0.value)")
}
```

### Clearing values

Clearing (removing, deleting, you name it) records is simple as well.

```swift
try await fdb.clear(key: childSubspace["concrete_record"])

// OR
try await fdb.clear(key: rootSubspace["child"]["subspace"]["concrete_record"])

// OR EVEN
try await fdb.clear(key: rootSubspace["child", "subspace", "concrete_record"])

// OR EVEN (this is not OK, but still possible :)
try await fdb.clear(key: rootSubspace["child", FDB.Null, FDB.Tuple("foo", "bar"), "concrete_record"])

// clears whole subspace, including "concrete_record" key
try await fdb.clear(range: childSubspace.range)
```

### Atomic operations

FoundationDB also supports atomic operations like `ADD`, `AND`, `OR`, `XOR` and stuff like that
(please refer to [docs](https://apple.github.io/foundationdb/api-c.html#c.FDBMutationType)).
You can perform any of these operations with `atomic(_ op:key:value:)` method:

```swift
try await fdb.atomic(.add, key: key, value: 1)
```

Knowing that most popular atomic operation is increment (or decrement), I added handy syntax sugar:

```swift
try await fdb.increment(key: key)

// OR returning incremented value, which is always Int64
let result: Int64 = try await fdb.increment(key: key)

// OR
let result = try await fdb.increment(key: key, value: 2)
```

However, keep in mind that example above isn't atomic anymore.

And decrement, which is just a proxy for `increment(key:value:)`, just inverting the `value`:

```swift
let result = try await fdb.decrement(key: key)

// OR
let result = try await fdb.decrement(key: key, value: 2)
```

### Transactions

All previous examples are utilizing `FDB` object methods which are implicitly transactional. If you would like
to perform more than one operation within one transaction (and experience all delights
of [ACID](https://en.wikipedia.org/wiki/ACID_(computer_science))), you should first begin transaction using
`begin()` method on `FDB` object context and then do your stuff (just don't forget to `commit()` it in the end,
by default transactions roll back if not committed explicitly, or after timeout of 5 seconds):

```swift
let transaction = try fdb.begin()

transaction.set(key: "someKey", value: someBytes)

try await transaction.commit()

// OR
transaction.reset()

// OR
transaction.cancel()
```

Or you can just leave transaction object in place and it resets & destroys itself on `deinit`.
Consider it auto-rollback. Please refer to official docs on reset and cancel behaviour:
https://apple.github.io/foundationdb/api-c.html#c.fdb_transaction_reset

It's not really necessary to commit readonly transaction though :)

Additionally you may set transaction options using `transaction.setOption(_:)` method:

```swift
let transaction: AnyFDBTransaction = ...
try transaction.setOption(.transactionLoggingEnable(identifier: "debuggable_transaction"))
try transaction.setOption(.snapshotRywDisable)
```

See [`Transaction+Options.swift`](Sources/FDB/Transaction/Transaction%2BOptions.swift) for a complete list of options.

### Conflicts, retries and `withTransaction`

Since FoundationDB is _quite_ a transactional database, sometimes `commit`s might not succeed due to serialization
failures (more commonly and mistakenly known as deadlocks). This can happen when two or more transactions create
overlapping conflict ranges. Or, simply speaking, when they try to access or modify same keys
(unless they are not in `snapshot` read mode) at the same time. This is expected (and, in a way, welcomed) behaviour,
because this is how ACID works.

In these [not-so-rare] cases transaction is allowed to be replayed again.
How do you know if your transaction can be replayed? It's failed with a special error case`FDB.Error.transactionRetry`.
If your transaction is failed with this particular error, it means that the transaction has already been rolled back
to its initial state and is ready to be executed again.

You can implement this retry logic manually or you can just use `FDB` instance method `withTransaction`.
Following example should be self-explanatory:

```swift
let maybeString: String? = try await fdb.withTransaction { transaction in
    guard let bytes: Bytes = try await transaction.get(key: key) else {
        return nil
    }
    try await transaction.commit()
    return String(bytes: bytes, encoding: .ascii)
}
```

Thus your block of code will be gently retried until transaction is successfully committed
(or until databases decides that it's been retried enough times and _it's time to let it go_).

### Writing to Versionstamped Keys

As a special type of atomic operation, values can be written to special keys that are guaranteed to be unique.
These keys make use of an incomplete versionstamp within their tuples, which will be completed by the underlying cluster
when data is written. The Versionstamp that was used within a transaction can then be retrieved so it can be
referenced elsewhere.

An incomplete versionstamp can be created and added to tuples using the `FDB.Versionstamp()` initializer.
The `userData` field is optional, and serves to further order keys if multiple are written within the same transaction.

Within a transaction's block, the `set(versionstampedKey:value:)` method can be used to write to keys with incomplete
versionstamps. This method will search the key for an incomplete versionstamp, and if one is found, will flag it to be
replaced by a complete versionstamp once it's written to the cluster. If an incomplete versionstamp was not found,
a `FDB.Error.missingIncompleteVersionstamp` error will be thrown.

If you need the complete versionstamp that was used within the key, you can call `getVersionstamp()` before
the transaction is committed. Note that this method must be called within the same transaction that a versionstamped key
was written in, otherwise it won't know which versionstamp to return. Also note that this versionstamp does not include
any user data that was associated with it, since it will be the same versionstamp no matter how many versionstamped keys
were written.

```swift
let keyWithVersionstampPlaceholder = self.subspace[FDB.Versionstamp(userData: 42)]["anotherKey"]
let valueToWrite: String = "Hello, World!"

var versionstamp: FDB.Versionstamp = try await fdb.withTransaction { transaction in
    try transaction.set(versionstampedKey: keyWithVersionstampPlaceholder, value: Bytes(valueToWrite.utf8))
    try await transaction.commit()
    return try await transaction.getVersionstamp()
}

versionstamp.userData = 42
let actualKey = self.subspace[versionstamp]["anotherKey"]

// ... return it to user, save it as a reference to another entry, etc…
```

### Complete example

```swift
let key = FDB.Subspace("1337")["322"]

let resultString: String = try await fdb.withTransaction { transaction in
    try transaction.setOption(.timeout(milliseconds: 5000))
    try transaction.setOption(.snapshotRywEnable)

    transaction.set(key: key, value: Bytes([1, 2, 3]))

    guard let bytes = try await transaction.get(key: key, snapshot: true) else {
        throw MyApplicationError.Something("Bytes are not bytes")
    }
    guard let string = String(bytes: bytes, encoding: .ascii) else {
        throw MyApplicationError.Something("String is not string")
    }

    try await transaction.commit()

    return string
}

print("My string is '\(resultString)'")
```

### Debugging/logging

FDBSwift supports official community [Swift-Log](https://github.com/apple/swift-log) library, therefore you might plug
your custom logger into `FDB` class:

```swift
FDB.logger = myCustomLogger

// or project-wise

LoggingSystem.bootstrap(MyLogHandler.init)
```

See Swift-Log [docs](https://github.com/apple/swift-log#on-the-implementation-of-a-logging-backend-a-loghandler) for
more details on custom loggers.

By default FDBSwift uses very basic factory `stdout` logger with `.info` default log level (shouldn't be flooded).
If something goes wrong and/or you're not sure what's happening, you just change log level to `.debug`, just like that:

```swift
FDB.logger.logLevel = .debug
```

## Troubleshooting

### Package doesn't compile, something like `Undefined symbols for architecture` and tons of similar crap. Send help.

You haven't properly installed `pkg-config` for FoundationDB, see [Installation section](#installation).

### Package does compile in macOS, but in runtime I'm getting error `The bundle “FDBTests” couldn’t be loaded because it is damaged or missing necessary resources. Try reinstalling the bundle`. What do?

Execute this magic command in console:
`install_name_tool -id /usr/local/lib/libfdb_c.dylib /usr/local/lib/libfdb_c.dylib`.

Shoutout to @dimitribouniol and his
[https://github.com/kirilltitov/FDBSwift/issues/70#issuecomment-726421104](marvelous investigation).

### I'm getting strange error on second operation: `API version already set`. Should I rethink my life?

(Rethinking hence analyzing things is always good) You tried to create more than one instance of FDB class, which is
a) prohibited
b) not needed at all since one instance is just enough for any application
(if not, consider horizontal scaling, FDB absolutely shouldn't be a bottleneck of your application).
Strictly speaking, it's not very ok, there should be a way of creating more than one of FDB connection in a runtime,
and I will definitely try to make it possible. Still, I don't think that FDB connection pooling is a good idea,
it already does everything for you.

## Warnings

Though I aim for full interlanguage compatibility of Tuple layer, I don't guarantee it. During development I refered
to Python implementation, but there might be slight differences (like unicode string and byte string packing,
see [design doc](https://github.com/apple/foundationdb/blob/master/design/tuple.md) on strings
and [my comments](Tests/FDBTests/TupleTests.swift) on that). In general it's should be quite compatible already.
Probably one day I'll spend some time on ensuring packing compatibility, but that's not high priority for me.

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
* ✅ Auto transaction retry if allowed and appropriate
* ✅ 🎉 Even morer verbose (Swift-Log)
* ✅ The rest of tuple pack/unpack (only floats, I think?) (also Bool and UUID)
* ✅ Adopt `async/await`, yeah, boiiiiiiiiii
* ✅ Drop Swift-NIO support (not because it's something bad, but because it's not really necessary here anymore;
we still love it tho)
* More sugar for atomic operations
* The rest of C API (watches?)
* Directories
* Drop VR support
