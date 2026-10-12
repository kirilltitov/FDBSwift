// Directory layer instructions of the binding tester
// (bindings/bindingtester/spec/directoryLayerTester.md, reference: bindings/python/tests/directory_extension.py).

import FDB
import Foundation

/// An entry of the directory list
enum DirectoryEntry {
    case subspace(FDB.Subspace)
    case layer(FDB.DirectoryLayer)
    case directory(FDB.DirectorySubspace)

    /// Raw prefix (`rawPrefix` in Python), defined for subspaces and directories, including partitions
    var rawPrefix: Bytes {
        get throws {
            switch self {
            case let .subspace(subspace): return subspace.prefix
            case let .directory(directory): return directory.prefix
            case .layer: throw TesterError(description: "Directory layer has no prefix")
            }
        }
    }

    /// The subspace for subspace operations (packing, ranges etc.)
    var subspace: FDB.Subspace {
        get throws {
            switch self {
            case let .subspace(subspace): return subspace
            case let .directory(directory): return try directory.subspace
            case .layer: throw TesterError(description: "Directory layer is not a subspace")
            }
        }
    }
}

/// Directory state of a tester thread
final class DirectoryState: @unchecked Sendable {
    var list: [DirectoryEntry?] = [.layer(.default)]
    var index = 0
    var errorIndex = 0
}

let operationsCreatingDirectories: Set<String> = [
    "DIRECTORY_CREATE_SUBSPACE",
    "DIRECTORY_CREATE_LAYER",
    "DIRECTORY_CREATE_OR_OPEN",
    "DIRECTORY_CREATE",
    "DIRECTORY_OPEN",
    "DIRECTORY_MOVE",
    "DIRECTORY_MOVE_TO",
    "DIRECTORY_OPEN_SUBSPACE",
]

extension StackMachine {
    func executeDirectory(op: String, index: Int, isDatabase: Bool, isSnapshot: Bool) async {
        do {
            try await self.executeDirectoryOperation(op: op, index: index, isDatabase: isDatabase, isSnapshot: isSnapshot)
        } catch {
            if operationsCreatingDirectories.contains(op) {
                self.directories.list.append(nil)
            }
            self.push(index, bytes("DIRECTORY_ERROR"))
        }
    }

    private func executeDirectoryOperation(op: String, index: Int, isDatabase: Bool, isSnapshot: Bool) async throws {
        let state = self.directories
        guard state.list.indices.contains(state.index) else {
            throw TesterError(description: "Invalid directory index \(state.index)")
        }
        let current = state.list[state.index]

        switch op {
        case "DIRECTORY_CREATE_SUBSPACE":
            let path = try await self.popTuple()
            let rawPrefix = try await self.pop().asBytes
            state.list.append(.subspace(FDB.Subspace(prefix: rawPrefix).subspace(FDB.Tuple(elements: path))))

        case "DIRECTORY_CREATE_LAYER":
            let params = try await self.pop(3)
            let entries = try [params[0], params[1]].map { element -> DirectoryEntry? in
                let index = Int(try element.asInt)
                guard state.list.indices.contains(index) else {
                    throw TesterError(description: "Invalid directory index \(index)")
                }
                return state.list[index]
            }
            guard let nodeEntry = entries[0], let contentEntry = entries[1] else {
                state.list.append(nil)
                return
            }
            state.list.append(.layer(FDB.DirectoryLayer(
                nodeSubspace: FDB.Subspace(prefix: try nodeEntry.rawPrefix),
                contentSubspace: FDB.Subspace(prefix: try contentEntry.rawPrefix),
                allowManualPrefixes: try params[2].asInt == 1
            )))

        case "DIRECTORY_CHANGE":
            state.index = Int(try await self.pop().asInt)
            guard state.list.indices.contains(state.index) else {
                throw TesterError(description: "Invalid directory index \(state.index)")
            }
            if state.list[state.index] == nil {
                state.index = state.errorIndex
            }

        case "DIRECTORY_SET_ERROR_INDEX":
            state.errorIndex = Int(try await self.pop().asInt)

        case "DIRECTORY_CREATE_OR_OPEN":
            let path = try Self.path(try await self.popTuple())
            let layer = try Self.optionalBytes(try await self.pop())
            let directory = try await self.perform(database: isDatabase) { tr in
                switch try Self.directory(current) {
                case let .layer(layer_): try await layer_.createOrOpen(path, layer: layer, in: tr)
                case let .directory(directory): try await directory.createOrOpen(path, layer: layer, in: tr)
                }
            }
            state.list.append(.directory(directory))

        case "DIRECTORY_CREATE":
            let path = try Self.path(try await self.popTuple())
            let params = try await self.pop(2)
            let layer = try Self.optionalBytes(params[0])
            let prefix = try Self.optionalBytes(params[1])
            let directory = try await self.perform(database: isDatabase) { tr in
                switch try Self.directory(current) {
                case let .layer(layer_): try await layer_.create(path, layer: layer, prefix: prefix, in: tr)
                case let .directory(directory): try await directory.create(path, layer: layer, prefix: prefix, in: tr)
                }
            }
            state.list.append(.directory(directory))

        case "DIRECTORY_OPEN":
            let path = try Self.path(try await self.popTuple())
            let layer = try Self.optionalBytes(try await self.pop())
            let directory = try await self.perform(database: isDatabase) { tr in
                switch try Self.directory(current) {
                case let .layer(layer_): try await layer_.open(path, layer: layer, snapshot: isSnapshot, in: tr)
                case let .directory(directory):
                    try await directory.open(path, layer: layer, snapshot: isSnapshot, in: tr)
                }
            }
            state.list.append(.directory(directory))

        case "DIRECTORY_MOVE":
            let oldPath = try Self.path(try await self.popTuple())
            let newPath = try Self.path(try await self.popTuple())
            let directory = try await self.perform(database: isDatabase) { tr in
                switch try Self.directory(current) {
                case let .layer(layer): try await layer.move(oldPath, to: newPath, in: tr)
                case let .directory(directory): try await directory.move(oldPath, to: newPath, in: tr)
                }
            }
            state.list.append(.directory(directory))

        case "DIRECTORY_MOVE_TO":
            let newPath = try Self.path(try await self.popTuple())
            guard case let .directory(directory) = try Self.directory(current) else {
                throw FDB.Error.directoryRootOperation
            }
            let moved = try await self.perform(database: isDatabase) { tr in
                try await directory.move(to: newPath, in: tr)
            }
            state.list.append(.directory(moved))

        case "DIRECTORY_REMOVE", "DIRECTORY_REMOVE_IF_EXISTS":
            let path = try await self.popOptionalPath()
            let ifExists = op == "DIRECTORY_REMOVE_IF_EXISTS"
            try await self.perform(database: isDatabase) { tr in
                switch try Self.directory(current) {
                case let .layer(layer):
                    if ifExists {
                        try await layer.removeIfExists(path, in: tr)
                    } else {
                        try await layer.remove(path, in: tr)
                    }
                case let .directory(directory):
                    if ifExists {
                        try await directory.removeIfExists(path, in: tr)
                    } else {
                        try await directory.remove(path, in: tr)
                    }
                }
            }

        case "DIRECTORY_LIST":
            let path = try await self.popOptionalPath()
            let names = try await self.perform(database: isDatabase) { tr in
                try await Self.list(current, path, snapshot: isSnapshot, in: tr)
            }
            self.push(index, .bytes(FDB.Tuple(elements: names.map(FDB.TupleElement.string)).packed))

        case "DIRECTORY_EXISTS":
            let path = try await self.popOptionalPath()
            let exists = try await self.perform(database: isDatabase) { tr in
                try await Self.exists(current, path, snapshot: isSnapshot, in: tr)
            }
            self.push(index, .int(exists ? 1 : 0))

        case "DIRECTORY_PACK_KEY":
            let tuple = try await self.popTuple()
            self.push(index, .bytes(try Self.unwrap(current).subspace.subspace(FDB.Tuple(elements: tuple)).prefix))

        case "DIRECTORY_UNPACK_KEY":
            let key = try await self.pop().asBytes
            for element in try Self.unwrap(current).subspace.unpack(key).elements {
                self.push(index, element)
            }

        case "DIRECTORY_RANGE":
            let tuple = try await self.popTuple()
            let range = try Self.unwrap(current).subspace.subspace(FDB.Tuple(elements: tuple)).range
            self.push(index, .bytes(range.begin))
            self.push(index, .bytes(range.end))

        case "DIRECTORY_CONTAINS":
            let key = try await self.pop().asBytes
            self.push(index, .int(try Self.unwrap(current).subspace.contains(key) ? 1 : 0))

        case "DIRECTORY_OPEN_SUBSPACE":
            let tuple = try await self.popTuple()
            state.list.append(.subspace(try Self.unwrap(current).subspace.subspace(FDB.Tuple(elements: tuple))))

        case "DIRECTORY_LOG_SUBSPACE":
            let prefix = try await self.pop().asBytes
            let key = prefix + FDB.Tuple(state.index).packed
            let value = try Self.unwrap(current).subspace.prefix
            try await self.perform(database: isDatabase) { tr in tr.set(key: key, value: value) }

        case "DIRECTORY_LOG_DIRECTORY":
            let prefix = try await self.pop().asBytes
            let (path, layer): ([String], Bytes) = switch try Self.directory(current) {
            case .layer: ([], [])
            case let .directory(directory): (directory.path, directory.layer)
            }
            let logSubspace = FDB.Subspace(prefix: prefix)[state.index]
            try await self.perform(database: isDatabase) { tr in
                let exists = try await Self.exists(current, [], snapshot: false, in: tr)
                let children = exists ? try await Self.list(current, [], snapshot: false, in: tr) : []
                tr.set(key: logSubspace["path"], value: FDB.Tuple(elements: path.map(FDB.TupleElement.string)).packed)
                tr.set(key: logSubspace["layer"], value: FDB.Tuple(layer).packed)
                tr.set(key: logSubspace["exists"], value: FDB.Tuple(exists ? 1 : 0).packed)
                tr.set(
                    key: logSubspace["children"],
                    value: FDB.Tuple(elements: children.map(FDB.TupleElement.string)).packed
                )
            }

        case "DIRECTORY_STRIP_PREFIX":
            let key = try await self.pop().asBytes
            let prefix = try Self.unwrap(current).subspace.prefix
            guard key.starts(with: prefix) else {
                throw TesterError(description: "Key doesn't start with the prefix")
            }
            self.push(index, .bytes(Bytes(key[prefix.count...])))

        default:
            throw TesterError(description: "Unknown op \(op)")
        }
    }

    // MARK: Helpers

    private enum Directory {
        case layer(FDB.DirectoryLayer)
        case directory(FDB.DirectorySubspace)
    }

    private static func unwrap(_ entry: DirectoryEntry?) throws -> DirectoryEntry {
        guard let entry else {
            throw TesterError(description: "No directory")
        }
        return entry
    }

    private static func directory(_ entry: DirectoryEntry?) throws -> Directory {
        switch try Self.unwrap(entry) {
        case let .layer(layer): return .layer(layer)
        case let .directory(directory): return .directory(directory)
        case .subspace: throw TesterError(description: "Subspace is not a directory")
        }
    }

    private static func list(
        _ entry: DirectoryEntry?,
        _ path: [String],
        snapshot: Bool,
        in tr: borrowing FDB.Transaction
    ) async throws -> [String] {
        switch try Self.directory(entry) {
        case let .layer(layer): try await layer.list(path, snapshot: snapshot, in: tr)
        case let .directory(directory): try await directory.list(path, snapshot: snapshot, in: tr)
        }
    }

    private static func exists(
        _ entry: DirectoryEntry?,
        _ path: [String],
        snapshot: Bool,
        in tr: borrowing FDB.Transaction
    ) async throws -> Bool {
        switch try Self.directory(entry) {
        case let .layer(layer): try await layer.exists(path, snapshot: snapshot, in: tr)
        case let .directory(directory): try await directory.exists(path, snapshot: snapshot, in: tr)
        }
    }

    /// Pops a count and then that many items
    private func popTuple() async throws -> [FDB.TupleElement] {
        let count = Int(try await self.pop().asInt)
        return try await self.pop(count)
    }

    /// Pops a count (0 or 1) and then a path if it's 1
    private func popOptionalPath() async throws -> [String] {
        try await self.pop().asInt == 0 ? [] : try Self.path(try await self.popTuple())
    }

    private static func path(_ elements: [FDB.TupleElement]) throws -> [String] {
        try elements.map { element in
            switch element {
            case let .string(name):
                return name
            case let .bytes(bytes):
                guard let name = String(bytes: bytes, encoding: .utf8) else {
                    throw TesterError(description: "Invalid path element")
                }
                return name
            default:
                throw TesterError(description: "Invalid path element \(element)")
            }
        }
    }

    private static func optionalBytes(_ element: FDB.TupleElement) throws -> Bytes? {
        if case .null = element {
            return nil
        }
        return try element.asBytes
    }
}
