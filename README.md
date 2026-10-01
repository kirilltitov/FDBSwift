# FDBSwift v6 <img src="https://img.shields.io/badge/Swift-6.2+-brightgreen.svg" alt="Swift: 6.2+" /> <img src="https://img.shields.io/badge/FoundationDB-7.4-blue.svg" alt="FoundationDB: 7.4" />
> _Episode VI: These Aren't the Copies You're Looking For_

This is FoundationDB client for Swift. It's quite low-level, `Foundation`less (well, `FoundationEssentials`-only,
for `UUID`), strictly concurrency-checked (Swift 6 language mode) and built around ownership: transactions and futures
are non-copyable values with a well-defined lifetime, so a whole class of use-after-free and double-free bugs simply
doesn't compile anymore.

## Requirements

* Swift 6.2+ (tested with 6.4)
* macOS 15+ or Linux
* FoundationDB client library (`libfdb_c`) **7.4+**. The cluster itself may be older: `libfdb_c` 7.4 can talk to
  older clusters via the [multi-version client](https://apple.github.io/foundationdb/api-general.html#multi-version-client-api)
  (see `FDB.NetworkOption.externalClientDirectory(path:)`).

## Installation

Install FoundationDB client (and server, if you need a local one) from
[releases](https://github.com/apple/foundationdb/releases). Next part is tricky because CFDB module (C bindings)
won't link `libfdb_c` library on its own, and FoundationDB doesn't ship `pkg-config` during installation.
Therefore you must install it yourself. Run

```bash
./scripts/install_pkgconfig.sh
```

or copy `scripts/libfdb.pc` (choose your platform) to `/usr/local/lib/pkgconfig/` on macOS or
`/usr/lib/pkgconfig/libfdb.pc` on Linux.

```swift
.package(url: "https://github.com/kirilltitov/FDBSwift.git", from: "6.0.0"),
```

## Usage

### Database

```swift
// Default cluster file (FDB_CLUSTER_FILE env, ./fdb.cluster or the platform default)
let db = try FDB.Database()

// OR
let db = try FDB.Database(clusterFile: "/usr/local/etc/foundationdb/fdb.cluster")

// OR
let db = try FDB.Database(connectionString: "description:id@127.0.0.1:4500")
```

`Database` is `Sendable`, long-lived and meant to be shared. You may open as many databases as you like (even to
different clusters). Connection is established lazily, so connectivity problems surface as errors (or timeouts) of the
first transactions.

Under the hood there's the FoundationDB network: a process-wide singleton which is started automatically when the first
database is opened. If you need to configure it (TLS, tracing, external clients, knobs), do it before opening any database:

```swift
try FDB.Network.setOption(.tlsCertPath("/opt/fdb/tls/chain.pem"))
try FDB.Network.setOption(.tlsPassword("changeme"))
try FDB.Network.setOption(.externalClientDirectory(path: "/usr/lib/foundationdb/multiversion"))
```

Secrets (`tlsKeyBytes`, `tlsPassword`) are never logged.

### Keys, tuples and subspaces

Keys and values are bytes (`typealias Bytes = [UInt8]`). Anything conforming to `FDBKey` can be used as a key:
`Bytes`, `String`, `StaticString`, `FDB.Tuple` and `FDB.Subspace`.

Tuples (see [tuple layer](https://github.com/apple/foundationdb/blob/main/design/tuple.md)) are built with parameter
packs and packed into a single buffer right away, so a tuple key is as cheap as raw bytes:

```swift
let tuple = FDB.Tuple("users", 42, UUID(), 3.14, true, FDB.Null(), FDB.Tuple("nested", Bytes([0, 1, 2])))

// Typed unpacking, no `as?` casts
let (kind, id) = try FDB.Tuple(packed: bytes).unpack(as: String.self, Int.self)

// Or dynamic, when you don't know the structure in advance
let elements: [FDB.TupleElement] = try FDB.Tuple(packed: bytes).elements // [.string("users"), .int(42), ...]
```

Supported elements: `String`, `Bytes`, all integers up to 64 bits (full `Int64` and `UInt64` range), `Float`, `Double`,
`Bool`, `UUID`, `FDB.Versionstamp`, `FDB.Null`, nested `FDB.Tuple` and `Optional` of any of them (`nil` is `null`).
Conform your own types to `FDBTuplePackable`/`FDBTupleUnpackable` if you like.

Subspaces are key prefixes, the usual way of namespacing keys:

```swift
let users = FDB.Subspace("app", "users")
let email = users[42, "email"]                   // also a Subspace, hence a key
let (id, field) = try users.unpack(email).unpack(as: Int.self, String.self)
let everything = users.range                     // FDB.KeyRange of all keys in the subspace
```

### Transactions

The main API is `withTransaction`. It lends a transaction to the closure, commits it afterwards and retries the whole
closure on retryable errors (conflicts and such), following FoundationDB semantics
(`fdb_transaction_on_error`: backoff, retry limit, timeout):

```swift
let name: String? = try await db.withTransaction { tr in
    tr.set(key: users[42, "visits"], value: someBytes)

    guard let bytes = try await tr.get(key: users[42, "name"]).value() else {
        return nil
    }
    return String(decoding: bytes, as: UTF8.self)
}
```

The transaction is a non-copyable value (`~Copyable`), so it can't escape the closure, can't be destroyed twice and
can't be used after it's gone. The closure must be idempotent, as it may run more than once.

By default databases set a retry limit of 100 (without it FoundationDB retries conflicts *forever*); when it's exhausted
(or the error is not retryable at all), the last error is thrown. See `transactionRetryLimit` and `transactionTimeout`
parameters of `FDB.Database.init`.

Errors thrown by the closure that are not `FDB.Error`s are rethrown immediately, without retrying.

#### Futures and parallel reads

Reads return `FDB.Future`s: the request goes to the cluster immediately, the result is awaited later. Futures are
non-copyable too: awaited at most once (`value()` consumes it), released exactly once. To read several keys in
parallel, just issue all requests first:

```swift
try await db.withTransaction { tr in
    let a = tr.get(key: keyA)
    let b = tr.get(key: keyB)
    let c = tr.getReadVersion()
    return try await (a.value(), b.value(), c.value())
}
```

Cancelling the awaiting task cancels the FoundationDB operation as well (`FDB.Error.operationCancelled`).

#### Ranges

```swift
// Everything, as many batches as needed
let records: [FDB.KeyValue] = try await tr.getAll(users.range)
let lastTen = try await tr.getAll(users.range, limit: 10, reverse: true)

// Batch by batch, zero-copy: keys and values are `Span`s pointing straight into FoundationDB client memory.
// The next batch is already being fetched while you process the current one.
try await tr.forEachBatch(in: users.range) { batch in
    batch.forEach { key, value in
        total += value.count
    }
}

// Low-level single batch with key selectors, limits and streaming modes
let result: FDB.RangeResult = try await tr.getRange(
    begin: .firstGreaterThan(someKey),
    end: .firstGreaterOrEqual(users.range.end),
    limit: 100,
    mode: .exact
).value()
```

#### Writes, atomics, options

```swift
tr.set(key: key, value: bytes)
tr.clear(key: key)
tr.clear(range: users.range)
tr.atomic(.add, key: counter, value: Int64(1))
tr.atomic(.byteMax, key: key, value: bytes)
try tr.setOption(.timeout(milliseconds: 5000))
try tr.setOption(.priorityBatch)
```

### Versionstamps

```swift
let (_, versionstamp) = try await db.withVersionstampedTransaction { tr in
    try tr.set(versionstampedKey: log[FDB.Versionstamp(userVersion: 0), "event"], value: payload)
}
let actualKey = log[versionstamp.with(userVersion: 0), "event"]
```

The position of the incomplete versionstamp is tracked while the tuple is packed, no re-parsing involved. More than one
incomplete versionstamp in a key is an error.

### One-shot helpers

Each runs in its own transaction:

```swift
try await db.set(key: key, value: bytes)
let value: Bytes? = try await db.get(key: key)
let all = try await db.getAll(users.range)
try await db.clear(key: key)
try await db.clear(range: users.range)
try await db.increment(key: counter, by: 1) // pure atomic add, never conflicts
```

### Errors

`FDB.Error` is a struct holding the original FoundationDB error code, so nothing is lost for codes this package doesn't
know about. Well-known errors are static members, so they can be matched directly; predicates come from
FoundationDB itself:

```swift
do {
    ...
} catch FDB.Error.transactionTooOld {
    ...
} catch let error as FDB.Error where error.isMaybeCommitted {
    ...
}
```

Most of the API uses typed throws (`throws(FDB.Error)`).

### Logging

[swift-log](https://github.com/apple/swift-log). Pass your `Logger` to `FDB.Database.init(logger:)`; every operation is
logged at `trace` level (lazily, nothing is computed unless enabled).

## Migration from v5 to v6

v6 is a rewrite, the API is new. In short:

| v5 | v6 |
|---|---|
| `let fdb = FDB(clusterFile:)`, `connect()`, `disconnect()` | `let db = try FDB.Database(clusterFile:)`, network is managed by `FDB.Network` |
| `fdb.setOption(.TLSCertPath(path:))` | `FDB.Network.setOption(.tlsCertPath(_:))` |
| `AnyFDB`, `AnyFDBTransaction` protocols | concrete `FDB.Database` and `~Copyable` `FDB.Transaction` |
| `fdb.begin()` + `commit()` | `db.withTransaction { tr in ... }` (commits automatically) or `db.makeTransaction()` |
| `try await tr.get(key:)` | `try await tr.get(key:).value()` |
| `get(range:)`, `get(subspace:)` (first batch only) | `getAll(_:)` (all batches), `forEachBatch(in:)`, `getRange(begin:end:...)` |
| `FDB.Error` enum, `transactionRetry` | `FDB.Error` struct with raw `code`, retries via `fdb_transaction_on_error` |
| `AnyFDBKey.asFDBKey()` | `FDBKey.fdbKey` |
| `FDB.Tuple([...])`, `tuple.tuple[0] as? Int`, `getPackedFDBTupleValue()` | `FDB.Tuple(...)`, `unpack(as:)` / `elements`, `packed` |
| `FDB.Tuple(from:)` | `FDB.Tuple(packed:)` |
| `Versionstamp.userData` | `Versionstamp.userVersion` |
| `increment(key:value:) -> Int64` | `increment(key:by:)` (doesn't read the value, never conflicts) |
| `Logger.current` (LGNLog) | plain swift-log `Logger` passed to `Database` |

## Troubleshooting

### Package doesn't compile, something like `Undefined symbols for architecture` and tons of similar crap. Send help.

You haven't properly installed `pkg-config` for FoundationDB, see [Installation section](#installation).

### Package does compile in macOS, but in runtime I'm getting error `The bundle “FDBTests” couldn’t be loaded because it is damaged or missing necessary resources. Try reinstalling the bundle`. What do?

Execute this magic command in console:
`install_name_tool -id /usr/local/lib/libfdb_c.dylib /usr/local/lib/libfdb_c.dylib`.

Shoutout to [@dimitribouniol](https://github.com/dimitribouniol) and his
[marvelous investigation](https://github.com/kirilltitov/FDBSwift/issues/70#issuecomment-726421104).

### `api_version_not_supported` on start

Your `libfdb_c` is older than 7.4. Upgrade the client library (the cluster may stay older, see
[Requirements](#requirements)).

## TODOs

* Enterprise support, vendor WSDL, rewrite on ~Java~ ~Scala~ ~Kotlin~ Java 25
* Blockchain? ICO? VR? AR? AI?
* Rehab
* ✅ Proper errors (for real this time)
* ✅ Tuples, subspaces, ranges, atomics, versionstamps
* ✅ Adopt `async/await`, yeah, boiiiiiiiiii
* ✅ Adopt ownership: `~Copyable` all the things
* ✅ Strict concurrency
* ✅ More than one database per process
* ✅ Task cancellation
* ✅ Zero-copy range reads
* The rest of C API (watches, tenants, mapped ranges, ...)
* Directories
* `~Escapable` everything (as soon as lifetime annotations are out of experimental)
* Drop VR support
