# FDBSwift
### Fine. I'll do it myself.
#### It should definitely be better than Python bindings in Swift :D

This is FoundationDB wrapper for Swift. It's quite low-level, `Foundation`less (almost) and synchronous.

## Installation

Obviously, you need to install `FoundationDB` first. Download it from [official website](https://www.foundationdb.org/download/). Next part is tricky because subpackage [CFDBSwift](https://github.com/kirilltitov/CFDBSwift) (C bindings) won't link `libfdb_c` library on its own, and FoundationDB doesn't yet ship `pkg-config` during installation. Therefore you must install it yourself. Run `scripts/install_pkgconfig.sh` or copy `scripts/libfdb.pc` (choose your platform) to `/usr/local/lib/pkgconfig/` on macOS or `/usr/lib/pkgconfig/libfdb.pc` on Linux.

## Usage

By default (and in the very core) this wrapper, as well as C API, operates with byte keys and values (not pointers, but `Array<UInt8>`). For your convenience I created a protocol `FDBKey` which defines basic FDB key logics. This protocol is adopted by `String`, `[UInt8]`, `Tuple` and `Subspace` types (two latter are local). You may use any of these types as keys in all FDB methods which involve keys (like `set` / `get` / `clear`) or adopt this protocol by other types of your choice.

Values are always bytes (or `nil` if key not found). Why not `Data` you may ask? I'd like to stay `Foundation`less for as long as I can (srsly, import half of the world just for `Data` object which is a fancy wrapper around `NSData` which is a fancy wrapper around `[UInt8]`?) (Hast thou forgot that you need to wrap all your `Data` objects with `autoreleasepool` or otherwise you get _fancy_ memory leaks?), you can always convert bytes to `Data` with `Data(bytes: Bytes)` initializer (why would you want to do that? oh yeah, right, JSON... ok, but do it yourself plz, extensions to the rescue).

Ahem. Where was I? OK so you can use this package as library (`FDB`) or you can just clone this repo and play with `FDBTestDrive` product, I've done some tests there. Now, about library API.

```swift
// duh
import FDB

// Default cluster path depending on your OS
let fdb = FDB()
// OR
let fdb = FDB(cluster: "/usr/local/etc/foundationdb/fdb.cluster")

try fdb.set(key: "somekey", value: someBytes)
// OR
try fdb.set(key: Bytes([0, 1, 2, 3]), value: someBytes)
// OR
try fdb.set(key: Tuple("foo", nil, "bar", Tuple("baz", "sas"), "lul"), value: someBytes)
// OR
try fdb.set(key: Subspace("foo").subspace("bar"), value: someBytes)

// Value is `Bytes?`, unwrap it before usage
let value = try fdb.get(key: "someKey")

// dump subspace if you would like to see how it looks from the inside
let rootSubspace = Subspace("root")
// also check Subspace.swift for more details and usecases
let childSubspace = rootSubspace.subspace("child", "subspace")

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

let range = childSubspace.range

/*
  these two calls are completely equal (can't really come up with case when you need second form,
  but whatever, I've seen worse whims)
*/
let records = try fdb.get(range: range)
let records = try fdb.get(begin: range.begin, end: range.end)

records.forEach {
    dump("\($0.key) - \($0.value)")
    return
}

/*
  `fdb.get`, `fdb.set`, `fdb.clear` methods are implicitly transactional, but you can manually
  manage transactions (it gives you insane performance boost since transaction per operation
  is quite expensive)
*/
let transaction = try fdb.begin()

// By default transactions are NOT committed, you must do it explicitly or pass optional arg `commit`
try transaction.set(key: "someKey", value: someBytes, commit: true)

try transaction.commit()
// or
transaction.reset()
// or
transaction.cancel()
// Or you can just leave transaction object in place and it resets & destroys itself on `deinit`.
// Consider it auto-rollback.
// Please refer to official docs on reset and cancel behaviour:
// https://apple.github.io/foundationdb/api-c.html#c.fdb_transaction_reset
```

## Warning

This package is on ~extremely~ ~very~ quite early stage. Though I did some RW-tests on my machine (macOS), I do not recommend to use it in real production (yet) (soon tho).

## TODOs

* Asynchronous methods
* Network options
* ~Proper errors~
* The rest of C API
* ~There is a memory leak somewhere, find@eliminate~
* Enterprise support, vendor WSDL, rewrite on Java
* Drop enterprise support, rewrite on golang using react-native (pretty sure it will be a thing by that time)
* Blockchain? ICO? VR? AR?
* Rehab
* ~Transactions rollback~
* ~Tuples~ (including ~pack~ and unpack)
* Integer tuples
* ~Ranges~, ~subspaces~, directories
* ~Tests~
* Properly test on Linux
