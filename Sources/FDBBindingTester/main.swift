// Stack machine for the official FoundationDB binding tester
// (https://github.com/apple/foundationdb/tree/main/bindings/bindingtester).
//
// Usage: FDBBindingTester <prefix> <api version> [cluster file]
//
// Mirrors the reference Python tester (bindings/python/tests/tester.py): the binding tester runs the same randomly
// generated instructions through it and through this one and compares the results byte by byte.

import FDB
import Foundation
import Synchronization

// MARK: - Stack

/// A pending future on the stack: resolved (and cached) when popped
class Pending: @unchecked Sendable {
    func value() async -> FDB.TupleElement {
        fatalError("Must be overridden")
    }
}

final class PendingFuture<V>: Pending, @unchecked Sendable {
    private var future: FDB.Future<V>?
    private let convert: (V) -> FDB.TupleElement
    private var cached: FDB.TupleElement?

    init(_ future: consuming FDB.Future<V>, convert: @escaping (V) -> FDB.TupleElement) {
        self.future = consume future
        self.convert = convert
    }

    override func value() async -> FDB.TupleElement {
        if let cached = self.cached {
            return cached
        }
        let result: FDB.TupleElement
        if let future = self.future.take() {
            do {
                result = self.convert(try await future.value)
            } catch {
                result = errorElement(error)
            }
        } else {
            fatalError("Future is consumed, but no value is cached")
        }
        self.cached = result
        return result
    }
}

enum StackValue {
    case element(FDB.TupleElement)
    case pending(Pending)
}

struct StackItem {
    let index: Int
    var value: StackValue
}

let resultNotPresent = FDB.TupleElement.bytes(Bytes("RESULT_NOT_PRESENT".utf8))

func errorElement(_ error: FDB.Error) -> FDB.TupleElement {
    .bytes(FDB.Tuple(Bytes("ERROR".utf8), Bytes("\(error.code)".utf8)).packed)
}

func bytes(_ string: String) -> FDB.TupleElement {
    .bytes(Bytes(string.utf8))
}

/// Returns the first key which is greater than all keys starting with given prefix
func strinc(_ key: Bytes) -> Bytes {
    var key = key
    while key.last == 0xFF {
        key.removeLast()
    }
    precondition(!key.isEmpty, "Key must contain at least one byte not equal to 0xFF")
    key[key.count - 1] += 1
    return key
}

/// Transactions shared by all stack machines ("threads")
final class TransactionBox: @unchecked Sendable {
    let transaction: FDB.Transaction

    init(_ transaction: consuming FDB.Transaction) {
        self.transaction = transaction
    }
}

let transactions = Mutex<[Bytes: TransactionBox]>([:])

struct TesterError: Error, CustomStringConvertible {
    let description: String
}

// MARK: - Big integer arithmetic (the tester needs `SUB` on integers up to 2040 bits)

/// `a - b` as a canonical tuple element
func subtract(_ a: FDB.BigInt, _ b: FDB.BigInt) -> FDB.TupleElement {
    // a - b = a + (-b)
    let bIsNegative = !b.isNegative && !b.magnitude.isEmpty
    let isNegative: Bool
    let magnitude: Bytes
    if a.isNegative == bIsNegative {
        isNegative = a.isNegative
        magnitude = addMagnitudes(a.magnitude, b.magnitude)
    } else if compareMagnitudes(a.magnitude, b.magnitude) >= 0 {
        isNegative = a.isNegative
        magnitude = subtractMagnitudes(a.magnitude, b.magnitude)
    } else {
        isNegative = bIsNegative
        magnitude = subtractMagnitudes(b.magnitude, a.magnitude)
    }
    return FDB.BigInt(isNegative: isNegative, magnitude: magnitude)!.tupleElement
}

func compareMagnitudes(_ a: Bytes, _ b: Bytes) -> Int {
    if a.count != b.count {
        return a.count < b.count ? -1 : 1
    }
    for (x, y) in zip(a, b) where x != y {
        return x < y ? -1 : 1
    }
    return 0
}

/// Sum of two big-endian magnitudes
func addMagnitudes(_ a: Bytes, _ b: Bytes) -> Bytes {
    var result = Bytes()
    var carry = 0
    var i = a.count - 1, j = b.count - 1
    while i >= 0 || j >= 0 || carry > 0 {
        let sum = (i >= 0 ? Int(a[i]) : 0) + (j >= 0 ? Int(b[j]) : 0) + carry
        result.append(UInt8(sum & 0xFF))
        carry = sum >> 8
        i -= 1
        j -= 1
    }
    return result.reversed()
}

/// Difference of two big-endian magnitudes, `a >= b`
func subtractMagnitudes(_ a: Bytes, _ b: Bytes) -> Bytes {
    var result = Bytes()
    var borrow = 0
    var j = b.count - 1
    for i in stride(from: a.count - 1, through: 0, by: -1) {
        var difference = Int(a[i]) - (j >= 0 ? Int(b[j]) : 0) - borrow
        borrow = difference < 0 ? 1 : 0
        difference += borrow << 8
        result.append(UInt8(difference))
        j -= 1
    }
    return result.reversed()
}

// MARK: - Element accessors

extension FDB.TupleElement {
    var asBytes: Bytes {
        get throws {
            switch self {
            case let .bytes(value): return value
            case let .string(value): return Bytes(value.utf8)
            default: throw TesterError(description: "Expected bytes, got \(self)")
            }
        }
    }

    var asInt: Int64 {
        get throws {
            switch self {
            case let .int(value): return value
            case let .bool(value): return value ? 1 : 0
            default: throw TesterError(description: "Expected int, got \(self)")
            }
        }
    }

    /// Low 32 bits of an integer of any size (two's complement), like a ctypes `c_int` conversion
    var asTruncatedInt32: Int32 {
        get throws {
            let value: FDB.BigInt
            switch self {
            case let .int(int): value = FDB.BigInt(int)
            case let .uint(uint): value = FDB.BigInt(uint)
            case let .bigInt(bigInt): value = bigInt
            default: throw TesterError(description: "Expected int, got \(self)")
            }
            var low: UInt32 = 0
            for byte in value.magnitude.suffix(4) {
                low = low << 8 | UInt32(byte)
            }
            return Int32(bitPattern: value.isNegative ? 0 &- low : low)
        }
    }

    var asBool: Bool {
        get throws {
            switch self {
            case let .bool(value): return value
            case let .int(value): return value != 0
            default: throw TesterError(description: "Expected bool, got \(self)")
            }
        }
    }
}

// MARK: - Stack machine

final class StackMachine: @unchecked Sendable {
    let db: FDB.Database
    let prefix: Bytes
    var stack: [StackItem] = [] // the top is the last element
    var transactionName: Bytes
    var lastVersion: Int64 = 0
    var threads: [Task<Void, any Error>] = []
    let directories = DirectoryState()
    /// Active tenant, transactions are created from it if set
    var tenant: FDB.Tenant?
    /// Target of `_DATABASE` and `_TENANT` operations
    var target: any FDB.Transactor

    init(db: FDB.Database, prefix: Bytes) {
        self.db = db
        self.prefix = prefix
        self.transactionName = prefix
        self.target = db
    }

    // MARK: Stack operations

    func push(_ index: Int, _ element: FDB.TupleElement) {
        self.stack.append(StackItem(index: index, value: .element(element)))
    }

    func push(_ index: Int, _ pending: Pending) {
        self.stack.append(StackItem(index: index, value: .pending(pending)))
    }

    func popItem() async throws -> (index: Int, element: FDB.TupleElement) {
        guard let item = self.stack.popLast() else {
            throw TesterError(description: "Stack is empty")
        }
        switch item.value {
        case let .element(element): return (item.index, element)
        case let .pending(pending): return (item.index, await pending.value())
        }
    }

    func pop() async throws -> FDB.TupleElement {
        try await self.popItem().element
    }

    /// Pops `count` items, the top one first
    func pop(_ count: Int) async throws -> [FDB.TupleElement] {
        var result: [FDB.TupleElement] = []
        for _ in 0 ..< count {
            result.append(try await self.pop())
        }
        return result
    }

    // MARK: Transactions

    func newTransaction() throws {
        let source: any FDB.Transactor = self.tenant ?? self.db
        let box = TransactionBox(try source.makeTransaction())
        transactions.withLock { $0[self.transactionName] = box }
    }

    func currentTransaction() throws -> TransactionBox {
        if let box = transactions.withLock({ $0[self.transactionName] }) {
            return box
        }
        try self.newTransaction()
        return try self.currentTransaction()
    }

    /// Runs the body against the database (in its own retried transaction) or the current transaction
    func perform<T>(
        database: Bool,
        _ body: (borrowing FDB.Transaction) async throws -> T
    ) async throws -> T {
        if database {
            return try await self.target.withTransaction(body)
        }
        let box = try self.currentTransaction()
        return try await body(box.transaction)
    }

    // MARK: Run

    func run() async throws {
        let instructions = try await self.db.getAll(FDB.Subspace(self.prefix).range)

        for (index, instruction) in instructions.enumerated() {
            let elements = try FDB.Tuple(packed: instruction.value).elements
            guard case var .string(op) = elements[0] else {
                throw TesterError(description: "Invalid instruction \(elements)")
            }

            var isDatabase = false
            var isSnapshot = false
            self.target = self.db
            if op.hasSuffix("_DATABASE") {
                isDatabase = true
                op.removeLast("_DATABASE".count)
            } else if op.hasSuffix("_TENANT") {
                // Same as _DATABASE, but on the active tenant (if any)
                isDatabase = true
                if let tenant = self.tenant {
                    self.target = tenant
                }
                op.removeLast("_TENANT".count)
            } else if op.hasSuffix("_SNAPSHOT") {
                isSnapshot = true
                op.removeLast("_SNAPSHOT".count)
            }

            do {
                try await self.execute(
                    op: op,
                    argument: elements.count > 1 ? elements[1] : nil,
                    index: index,
                    isDatabase: isDatabase,
                    isSnapshot: isSnapshot
                )
            } catch let error as FDB.Error {
                self.push(index, errorElement(error))
            } catch let error as FDB.RangeError<Never> {
                switch error {
                case let .fdb(error): self.push(index, errorElement(error))
                }
            } catch {
                throw TesterError(description: "\(op) (instruction \(index)) failed: \(error)")
            }
        }

        for thread in self.threads {
            try await thread.value
        }
    }

    // MARK: Instructions

    func execute(op: String, argument: FDB.TupleElement?, index: Int, isDatabase: Bool, isSnapshot: Bool) async throws {
        switch op {
        // Data operations

        case "PUSH":
            self.push(index, argument!)
        case "DUP":
            guard let top = self.stack.last else {
                throw TesterError(description: "Stack is empty")
            }
            self.stack.append(top)
        case "EMPTY_STACK":
            self.stack = []
        case "SWAP":
            let depth = Int(try await self.pop().asInt)
            let top = self.stack.count - 1
            self.stack.swapAt(top, top - depth)
        case "POP":
            _ = try await self.pop()
        case "SUB":
            let values = try await self.pop(2)
            self.push(index, subtract(try FDB.BigInt(tupleElement: values[0]), try FDB.BigInt(tupleElement: values[1])))
        case "CONCAT":
            let values = try await self.pop(2)
            switch (values[0], values[1]) {
            case let (.string(a), .string(b)): self.push(index, .string(a + b))
            default: self.push(index, .bytes(try values[0].asBytes + values[1].asBytes))
            }
        case "WAIT_FUTURE":
            let (itemIndex, element) = try await self.popItem()
            self.push(itemIndex, element)
        case "LOG_STACK":
            let prefix = try await self.pop().asBytes
            var entries: [(stackIndex: Int, index: Int, element: FDB.TupleElement)] = []
            while !self.stack.isEmpty {
                let stackIndex = self.stack.count - 1
                let (itemIndex, element) = try await self.popItem()
                entries.append((stackIndex, itemIndex, element))
                if entries.count == 100 {
                    try await self.logStack(prefix: prefix, entries: entries)
                    entries = []
                }
            }
            try await self.logStack(prefix: prefix, entries: entries)

        // Transactions

        case "NEW_TRANSACTION":
            try self.newTransaction()
        case "USE_TRANSACTION":
            self.transactionName = try await self.pop().asBytes
            _ = try self.currentTransaction()
        case "ON_ERROR":
            let code = Int32(try await self.pop().asInt)
            let future = try self.currentTransaction().transaction.onError(FDB.Error(code: code))
            self.push(index, PendingFuture(future) { _ in resultNotPresent })
        case "COMMIT":
            let future = try self.currentTransaction().transaction.commit()
            self.push(index, PendingFuture(future) { _ in resultNotPresent })
        case "RESET":
            try self.currentTransaction().transaction.reset()
        case "CANCEL":
            try self.currentTransaction().transaction.cancel()
        case "GET_READ_VERSION":
            self.lastVersion = try await self.perform(database: false) { tr in
                try await tr.getReadVersion().value
            }
            self.push(index, bytes("GOT_READ_VERSION"))
        case "SET_READ_VERSION":
            try self.currentTransaction().transaction.setReadVersion(self.lastVersion)
        case "GET_COMMITTED_VERSION":
            self.lastVersion = try self.currentTransaction().transaction.getCommittedVersion()
            self.push(index, bytes("GOT_COMMITTED_VERSION"))
        case "GET_APPROXIMATE_SIZE":
            _ = try await self.currentTransaction().transaction.getApproximateSize().value
            self.push(index, bytes("GOT_APPROXIMATE_SIZE"))
        case "GET_VERSIONSTAMP":
            let future = try self.currentTransaction().transaction.getVersionstamp()
            self.push(index, PendingFuture(future) { versionstamp in
                var result = Bytes()
                withUnsafeBytes(of: versionstamp.transactionCommitVersion.bigEndian) { result.append(contentsOf: $0) }
                withUnsafeBytes(of: versionstamp.batchNumber.bigEndian) { result.append(contentsOf: $0) }
                return .bytes(result)
            })
        case "DISABLE_WRITE_CONFLICT":
            try self.currentTransaction().transaction.setOption(.nextWriteNoWriteConflictRange)

        // Reads

        case "GET":
            let key = try await self.pop().asBytes
            if isDatabase {
                let value = try await self.target.get(key: key)
                self.push(index, value.map(FDB.TupleElement.bytes) ?? resultNotPresent)
            } else {
                let future = try self.currentTransaction().transaction.get(key: key, snapshot: isSnapshot)
                self.push(index, PendingFuture(future) { value in value.map(FDB.TupleElement.bytes) ?? resultNotPresent })
            }
        case "GET_KEY":
            let params = try await self.pop(4)
            let selector = FDB.KeySelector(
                key: try params[0].asBytes,
                orEqual: try params[1].asBool,
                offset: Int32(try params[2].asInt)
            )
            let prefix = try params[3].asBytes
            let result = try await self.perform(database: isDatabase) { tr in
                try await tr.getKey(selector, snapshot: isSnapshot).value
            }
            if result.starts(with: prefix) {
                self.push(index, .bytes(result))
            } else if result.lexicographicallyPrecedes(prefix) {
                self.push(index, .bytes(prefix))
            } else {
                self.push(index, .bytes(strinc(prefix)))
            }
        case "GET_RANGE":
            let params = try await self.pop(5)
            try await self.pushRange(
                index: index,
                begin: .firstGreaterOrEqual(try params[0].asBytes),
                end: .firstGreaterOrEqual(try params[1].asBytes),
                limit: params[2], reverse: params[3], mode: params[4],
                isDatabase: isDatabase, isSnapshot: isSnapshot
            )
        case "GET_RANGE_STARTS_WITH":
            let params = try await self.pop(4)
            let prefix = try params[0].asBytes
            try await self.pushRange(
                index: index,
                begin: .firstGreaterOrEqual(prefix),
                end: .firstGreaterOrEqual(strinc(prefix)),
                limit: params[1], reverse: params[2], mode: params[3],
                isDatabase: isDatabase, isSnapshot: isSnapshot
            )
        case "GET_RANGE_SELECTOR":
            let params = try await self.pop(10)
            try await self.pushRange(
                index: index,
                begin: FDB.KeySelector(
                    key: try params[0].asBytes, orEqual: try params[1].asBool, offset: Int32(try params[2].asInt)
                ),
                end: FDB.KeySelector(
                    key: try params[3].asBytes, orEqual: try params[4].asBool, offset: Int32(try params[5].asInt)
                ),
                limit: params[6], reverse: params[7], mode: params[8],
                prefixFilter: try params[9].asBytes,
                isDatabase: isDatabase, isSnapshot: isSnapshot
            )
        case "GET_ESTIMATED_RANGE_SIZE":
            let params = try await self.pop(2)
            let range = FDB.KeyRange(begin: try params[0].asBytes, end: try params[1].asBytes)
            _ = try await self.currentTransaction().transaction.getEstimatedRangeSizeBytes(range).value
            self.push(index, bytes("GOT_ESTIMATED_RANGE_SIZE"))
        case "GET_RANGE_SPLIT_POINTS":
            let params = try await self.pop(3)
            let range = FDB.KeyRange(begin: try params[0].asBytes, end: try params[1].asBytes)
            _ = try await self.currentTransaction().transaction
                .getRangeSplitPoints(range, chunkSize: try params[2].asInt).value
            self.push(index, bytes("GOT_RANGE_SPLIT_POINTS"))

        // Writes

        case "SET":
            let params = try await self.pop(2)
            let key = try params[0].asBytes
            let value = try params[1].asBytes
            try await self.perform(database: isDatabase) { tr in tr.set(key: key, value: value) }
            self.pushResultNotPresent(index: index, if: isDatabase)
        case "CLEAR":
            let key = try await self.pop().asBytes
            try await self.perform(database: isDatabase) { tr in tr.clear(key: key) }
            self.pushResultNotPresent(index: index, if: isDatabase)
        case "CLEAR_RANGE":
            let params = try await self.pop(2)
            let range = FDB.KeyRange(begin: try params[0].asBytes, end: try params[1].asBytes)
            try await self.perform(database: isDatabase) { tr in tr.clear(range: range) }
            self.pushResultNotPresent(index: index, if: isDatabase)
        case "CLEAR_RANGE_STARTS_WITH":
            let prefix = try await self.pop().asBytes
            let range = FDB.KeyRange(begin: prefix, end: strinc(prefix))
            try await self.perform(database: isDatabase) { tr in tr.clear(range: range) }
            self.pushResultNotPresent(index: index, if: isDatabase)
        case "ATOMIC_OP":
            let params = try await self.pop(3)
            guard case let .string(opName) = params[0], let mutation = mutationTypes[opName] else {
                throw TesterError(description: "Unknown atomic op \(params[0])")
            }
            let key = try params[1].asBytes
            let value = try params[2].asBytes
            try await self.perform(database: isDatabase) { tr in tr.atomic(mutation, key: key, value: value) }
            self.pushResultNotPresent(index: index, if: isDatabase)
        case "READ_CONFLICT_RANGE", "WRITE_CONFLICT_RANGE":
            let params = try await self.pop(2)
            let range = FDB.KeyRange(begin: try params[0].asBytes, end: try params[1].asBytes)
            let box = try self.currentTransaction()
            if op == "READ_CONFLICT_RANGE" {
                try box.transaction.addReadConflict(range: range)
            } else {
                try box.transaction.addWriteConflict(range: range)
            }
            self.push(index, bytes("SET_CONFLICT_RANGE"))
        case "READ_CONFLICT_KEY", "WRITE_CONFLICT_KEY":
            let key = try await self.pop().asBytes
            let box = try self.currentTransaction()
            if op == "READ_CONFLICT_KEY" {
                try box.transaction.addReadConflict(key: key)
            } else {
                try box.transaction.addWriteConflict(key: key)
            }
            self.push(index, bytes("SET_CONFLICT_KEY"))

        // Tuples

        case "TUPLE_PACK":
            let count = Int(try await self.pop().asInt)
            self.push(index, .bytes(FDB.Tuple(elements: try await self.pop(count)).packed))
        case "TUPLE_PACK_WITH_VERSIONSTAMP":
            let prefix = try await self.pop().asBytes
            let count = Int(try await self.pop().asInt)
            let tuple = FDB.Tuple(elements: try await self.pop(count))
            do {
                guard let offset = try tuple.incompleteVersionstampOffset() else {
                    self.push(index, bytes("ERROR: NONE"))
                    return
                }
                var packed = prefix + tuple.packed
                withUnsafeBytes(of: UInt32(prefix.count + offset).littleEndian) { packed.append(contentsOf: $0) }
                self.push(index, bytes("OK"))
                self.push(index, .bytes(packed))
            } catch FDB.Error.multipleIncompleteVersionstamps {
                self.push(index, bytes("ERROR: MULTIPLE"))
            }
        case "TUPLE_UNPACK":
            let packed = try await self.pop().asBytes
            for element in try FDB.Tuple(packed: packed).elements {
                self.push(index, .bytes(FDB.Tuple(elements: [element]).packed))
            }
        case "TUPLE_RANGE":
            let count = Int(try await self.pop().asInt)
            let packed = FDB.Tuple(elements: try await self.pop(count)).packed
            self.push(index, .bytes(packed + [0x00]))
            self.push(index, .bytes(packed + [0xFF]))
        case "TUPLE_SORT":
            let count = Int(try await self.pop().asInt)
            let tuples = try await self.pop(count).map { element in try FDB.Tuple(packed: try element.asBytes) }
            for tuple in tuples.sorted() {
                self.push(index, .bytes(tuple.packed))
            }
        case "ENCODE_FLOAT":
            let raw = try await self.pop().asBytes
            self.push(index, .float(Float(bitPattern: raw.reduce(0) { $0 << 8 | UInt32($1) })))
        case "ENCODE_DOUBLE":
            let raw = try await self.pop().asBytes
            self.push(index, .double(Double(bitPattern: raw.reduce(0) { $0 << 8 | UInt64($1) })))
        case "DECODE_FLOAT":
            guard case let .float(value) = try await self.pop() else {
                throw TesterError(description: "Expected float")
            }
            self.push(index, .bytes(withUnsafeBytes(of: value.bitPattern.bigEndian) { Bytes($0) }))
        case "DECODE_DOUBLE":
            guard case let .double(value) = try await self.pop() else {
                throw TesterError(description: "Expected double")
            }
            self.push(index, .bytes(withUnsafeBytes(of: value.bitPattern.bigEndian) { Bytes($0) }))

        // Threads

        case "START_THREAD":
            let machine = StackMachine(db: self.db, prefix: try await self.pop().asBytes)
            self.threads.append(Task { try await machine.run() })
        case "WAIT_EMPTY":
            let prefix = try await self.pop().asBytes
            let range = FDB.KeyRange(begin: prefix, end: strinc(prefix))
            try await self.db.withTransaction { tr in
                if try await !tr.getAll(range, limit: 1).isEmpty {
                    throw FDB.Error.notCommitted
                }
            }
            self.push(index, bytes("WAITED_FOR_EMPTY"))

        // Tenants

        case "TENANT_CREATE":
            try await self.db.createTenant(try await self.pop().asBytes)
            self.push(index, resultNotPresent)
        case "TENANT_DELETE":
            try await self.db.deleteTenant(try await self.pop().asBytes)
            self.push(index, resultNotPresent)
        case "TENANT_SET_ACTIVE":
            let tenant = try self.db.openTenant(try await self.pop().asBytes)
            self.tenant = tenant
            _ = try await tenant.getID().value
            self.push(index, bytes("SET_ACTIVE_TENANT"))
        case "TENANT_CLEAR_ACTIVE":
            self.tenant = nil
        case "TENANT_LIST":
            let params = try await self.pop(3)
            let tenants = try await self.db.listTenants(
                from: try params[0].asBytes,
                to: try params[1].asBytes,
                // Python passes the limit to C via ctypes, which silently truncates it to 32 bits
                limit: Int(try params[2].asTruncatedInt32)
            )
            self.push(index, .bytes(FDB.Tuple(elements: tenants.map { FDB.TupleElement.bytes($0.name) }).packed))
        case "TENANT_GET_ID":
            if let tenant = self.tenant {
                _ = try await tenant.getID().value
                self.push(index, bytes("GOT_TENANT_ID"))
            } else {
                self.push(index, bytes("NO_ACTIVE_TENANT"))
            }

        case "UNIT_TESTS":
            try await runUnitTests(db: self.db)

        case _ where op.hasPrefix("DIRECTORY_"):
            await self.executeDirectory(op: op, index: index, isDatabase: isDatabase, isSnapshot: isSnapshot)

        default:
            throw TesterError(description: "Unknown op \(op)")
        }
    }

    func pushResultNotPresent(index: Int, if condition: Bool) {
        if condition {
            self.push(index, resultNotPresent)
        }
    }

    func pushRange(
        index: Int,
        begin: FDB.KeySelector,
        end: FDB.KeySelector,
        limit: FDB.TupleElement,
        reverse: FDB.TupleElement,
        mode: FDB.TupleElement,
        prefixFilter: Bytes? = nil,
        isDatabase: Bool,
        isSnapshot: Bool
    ) async throws {
        let limit = Int(try limit.asInt)
        let reverse = try reverse.asBool
        guard let mode = FDB.StreamingMode(rawValue: Int32(try mode.asInt)) else {
            throw TesterError(description: "Invalid streaming mode \(mode)")
        }
        let records = try await self.perform(database: isDatabase) { tr in
            try await tr.getAll(begin: begin, end: end, limit: limit, mode: mode, snapshot: isSnapshot, reverse: reverse)
        }
        var elements: [FDB.TupleElement] = []
        for record in records where prefixFilter.map(record.key.starts(with:)) ?? true {
            elements.append(.bytes(record.key))
            elements.append(.bytes(record.value))
        }
        self.push(index, .bytes(FDB.Tuple(elements: elements).packed))
    }

    func logStack(prefix: Bytes, entries: [(stackIndex: Int, index: Int, element: FDB.TupleElement)]) async throws {
        try await self.db.withTransaction { tr in
            for entry in entries {
                let key = prefix + FDB.Tuple(entry.stackIndex, entry.index).packed
                let value = FDB.Tuple(elements: [entry.element]).packed
                tr.set(key: key, value: Array(value.prefix(40000)))
            }
        }
    }
}

let mutationTypes: [String: FDB.MutationType] = [
    "ADD": .add,
    "AND": .bitAnd, "BIT_AND": .bitAnd,
    "OR": .bitOr, "BIT_OR": .bitOr,
    "XOR": .bitXor, "BIT_XOR": .bitXor,
    "APPEND_IF_FITS": .appendIfFits,
    "MAX": .max,
    "MIN": .min,
    "SET_VERSIONSTAMPED_KEY": .setVersionstampedKey,
    "SET_VERSIONSTAMPED_VALUE": .setVersionstampedValue,
    "BYTE_MIN": .byteMin,
    "BYTE_MAX": .byteMax,
    "COMPARE_AND_CLEAR": .compareAndClear,
]

/// Features the stack machine doesn't cover (mirrors the essentials of bindings/python/tests/unit_tests.py)
func runUnitTests(db: FDB.Database) async throws {
    try await db.withTransaction { tr in
        try tr.setOption(.timeout(milliseconds: 60_000))
        try tr.setOption(.retryLimit(50))
        try tr.setOption(.maxRetryDelay(milliseconds: 100))
        try tr.setOption(.priorityBatch)
        try tr.setOption(.causalReadRisky)
        try tr.setOption(.debugTransactionIdentifier("my_transaction"))
        try tr.setOption(.logTransaction)
        try tr.setOption(.readLockAware)
        try tr.setOption(.lockAware)
        try tr.setOption(.readSystemKeys)
        _ = try await tr.get(key: Bytes([0xFF])).value
    }
}

// MARK: - Entry point

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("Usage: \(arguments[0]) <prefix> <api version> [cluster file]\n".utf8))
    exit(2)
}
do {
    guard let version = Int32(arguments[2]) else {
        throw FDB.Error.apiVersionInvalid
    }
    try FDB.Network.selectAPIVersion(version)
} catch {
    FileHandle.standardError.write(Data("Unsupported API version \(arguments[2]): \(error)\n".utf8))
    exit(2)
}

do {
    let db = try FDB.Database(clusterFile: arguments.count > 3 ? arguments[3] : nil)
    try await StackMachine(db: db, prefix: Bytes(arguments[1].utf8)).run()
    exit(0)
} catch {
    FileHandle.standardError.write(Data("Tester failed: \(error)\n".utf8))
    exit(1)
}
