# FDBSwift
### Fine. I'll do it myself.
#### It should definitely be better than Python bindings in Swift :D

This is FoundationDB wrapper for Swift. It's quite low-level, `Foundation`less (almost) and synchronous.

## Installation

Obviously, you need to install `FoundationDB` first. Download it from [official website](https://www.foundationdb.org/download/). Next part is tricky because subpackage [CFDBSwift](https://github.com/kirilltitov/CFDBSwift) (C bindings) won't link `libfdb_c` library on its own, and FoundationDB doesn't yet ship `pkg-config` during installation. Therefore you must install it yourself. Run `scripts/install_pkgconfig.sh` or copy `scripts/libfdb.pc` (choose your platform) to `/usr/local/lib/pkgconfig/` on macOS or `/usr/lib/pkgconfig/libfdb.pc` on Linux.

## Usage

By default this wrapper (as well as C API) operates with byte keys and values (not pointers, but `Array<UInt8>`). For your convenience I made proxy `set` / `get` / `remove` methods which operate `String` keys. It's not very OK, but whatever. Values are always bytes (or `nil` if key not found). Why not `Data` you may ask? I'd like to stay `Foundation`less for as long as I can (srsly, import half of the world just for `Data` object which is a fancy wrapper around `NSData` which is a fancy wrapper around `[UInt8]`?) (Hast thou forgot that you need to wrap all your `Data` objects with `autoreleasepool` or otherwise you get _fancy_ memory leaks?), you can always convert bytes to `Data` with `Data(bytes: Bytes)` initializer (why would you want to do that? oh yeah, right, JSON... ok, but do it yourself plz, extensions to the rescue).

Ahem. Where was I? OK so you can use this package as library (`FDB`) or you can just clone this repo and play with `FDBTestDrive` product, I've done some tests there. Now, about library API.

```swift
// Import, duh
import FDB

// Default path, wouldn't really like to hardcode it as default value
let fdb = FDB(cluster: "/usr/local/etc/foundationdb/fdb.cluster")

// Plz don't forget to wrap it with 'docatch' block and don't you dare to force 'try!' it.
// Always catch errors, you might get 'TransactionRetry' error which tells you that something went
// slightly wrong, but you can still get things done if you just replay all work within the same
// transaction (obviously, it works only if you manage the transaction by yourself).
// By the way, this method may return 'Transaction' object, but only if you explicitly passed
// 'commit: false' argument, just in case you would want to do things within that transaction,
// but in that case you must commit it by yourself (see below), or it will rollback
try fdb.set(key: "somekey", value: someBytes)

// Value is optional, unwrap it before usage
let value = try fdb.get(key: "someKey")

try fdb.remove(key: "someKey")

// Or you can manually manage transactions (it gives you insane performance boost since transaction
// per operation is quite expensive)
let transaction = try fdb.begin()

try fdb.set(key: "someKey", value: someBytes, transaction: transaction, commit: false)
//                                                                      ^^^^^^^^^^^^^  notice this plz

try transaction.commit()
// No explicit rollback yet, but you can just leave transaction object in place and it rollbacks itself
// on `deinit`
```

## Warning

This package is on extremely early stage. Though I did some RW-tests on my machine, I do not recommend to use it in real production.

## TODOs

* Asynchronous methods
* Network options
* Proper errors
* The rest of C API
* There is a memory leak somewhere, find@eliminate
* Enterprise support, vendor WSDL, rewrite on Java
* Drop enterprise support, rewrite on golang using react-native (pretty sure it will be a thing by that time)
* Blockchain? ICO? VR? AR?
* Transaction rollback
