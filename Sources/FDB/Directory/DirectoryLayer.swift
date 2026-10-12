extension FDB {
    /// Directory layer: a hierarchy of named directories, each mapped to a short, automatically allocated key prefix.
    ///
    /// Directories let applications use readable paths like `["app", "users"]` while keys stay short, and can be
    /// moved (renamed) without moving their contents. The metadata format is the same as in other FoundationDB
    /// bindings, so directories created by them can be opened here and vice versa.
    ///
    /// ```swift
    /// let users = try await FDB.DirectoryLayer.default.createOrOpen(["app", "users"], in: db)
    /// try await db.withTransaction { tr in
    ///     tr.set(key: try users.subspace[userID, "email"], value: ...)
    /// }
    /// ```
    ///
    /// All paths passed to a directory layer are relative to it (for the root directory layer they are absolute).
    public final class DirectoryLayer: Sendable {
        /// The default directory layer: metadata is stored under `\xFE`, contents get prefixes without a common prefix
        public static let `default` = DirectoryLayer()

        /// Layer of directory partitions, see ``createOrOpen(_:layer:in:)-(_,_,FDB.Transaction)``
        public static let partitionLayer: Bytes = Bytes("partition".utf8)

        static let version: (major: UInt32, minor: UInt32, patch: UInt32) = (1, 0, 0)
        static let subdirectories: Int = 0

        /// Subspace where the directory metadata is stored
        public let nodeSubspace: Subspace
        /// Subspace inside which prefixes of new directories are allocated
        public let contentSubspace: Subspace
        /// Whether directories may be created with an explicitly given prefix
        public let allowManualPrefixes: Bool

        /// Absolute path of this directory layer: empty unless it belongs to a partition
        let path: [String]
        let rootNode: Subspace
        let allocator: HighContentionAllocator

        /// Creates a directory layer.
        ///
        /// - parameters:
        ///   - nodeSubspace: Subspace where the directory metadata is stored
        ///   - contentSubspace: Subspace inside which prefixes of new directories are allocated
        ///   - allowManualPrefixes: Whether directories may be created with an explicitly given prefix
        public convenience init(
            nodeSubspace: Subspace = Subspace(prefix: [0xFE]),
            contentSubspace: Subspace = Subspace(prefix: []),
            allowManualPrefixes: Bool = false
        ) {
            self.init(
                nodeSubspace: nodeSubspace,
                contentSubspace: contentSubspace,
                allowManualPrefixes: allowManualPrefixes,
                path: []
            )
        }

        init(nodeSubspace: Subspace, contentSubspace: Subspace, allowManualPrefixes: Bool, path: [String]) {
            self.nodeSubspace = nodeSubspace
            self.contentSubspace = contentSubspace
            self.allowManualPrefixes = allowManualPrefixes
            self.path = path
            // The root node is the one whose contents are the node subspace
            self.rootNode = nodeSubspace[nodeSubspace.prefix]
            self.allocator = HighContentionAllocator(self.rootNode[Self.bytes("hca")])
        }

        // MARK: - Public API

        /// Opens the directory at given path, creating it (and missing parents) if it doesn't exist.
        ///
        /// - parameters:
        ///   - layer: If given, it's checked against the layer of an existing directory
        ///     (throws ``FDB/Error/directoryIncompatibleLayer`` on mismatch) or recorded for a new one.
        ///     Directories created with ``partitionLayer`` are partitions: separate directory layers whose
        ///     subdirectories all share the partition prefix.
        public func createOrOpen(
            _ path: [String],
            layer: Bytes? = nil,
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> DirectorySubspace {
            try await self.createOrOpen(tr, path, layer: layer, prefix: nil, allowCreate: true, allowOpen: true)
        }

        /// Opens an existing directory at given path, throws ``FDB/Error/directoryDoesNotExist`` if there is none.
        ///
        /// - parameters:
        ///   - layer: If given, it's checked against the layer of the directory
        ///   - snapshot: Use snapshot reads
        public func open(
            _ path: [String],
            layer: Bytes? = nil,
            snapshot: Bool = false,
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> DirectorySubspace {
            try await self.createOrOpen(
                tr, path, layer: layer, prefix: nil, allowCreate: false, allowOpen: true, snapshot: snapshot
            )
        }

        /// Creates a directory at given path (and missing parents),
        /// throws ``FDB/Error/directoryAlreadyExists`` if it exists.
        ///
        /// - parameters:
        ///   - layer: Recorded with the directory and checked by subsequent opens
        ///   - prefix: Physical prefix of the directory, allocated automatically by default.
        ///     Requires ``allowManualPrefixes``.
        public func create(
            _ path: [String],
            layer: Bytes? = nil,
            prefix: Bytes? = nil,
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> DirectorySubspace {
            try await self.createOrOpen(tr, path, layer: layer, prefix: prefix, allowCreate: true, allowOpen: false)
        }

        /// Moves the directory at `oldPath` to `newPath`.
        ///
        /// The physical prefix stays the same, so the contents are not moved and clients which already opened the
        /// directory are not affected. Throws if the source doesn't exist, the destination exists, the parent of the
        /// destination doesn't exist, or the paths are in different partitions.
        public func move(
            _ oldPath: [String],
            to newPath: [String],
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> DirectorySubspace {
            try await self.checkVersion(tr, writeAccess: true)

            if newPath.starts(with: oldPath) {
                throw .directoryMoveIntoSubdirectory
            }

            let oldNode = try await self.find(tr, oldPath).prefetched(tr)
            let newNode = try await self.find(tr, newPath).prefetched(tr)

            guard let oldSubspace = oldNode.subspace else {
                throw .directoryDoesNotExist
            }

            if oldNode.isInPartition || newNode.isInPartition {
                guard oldNode.isInPartition, newNode.isInPartition, oldNode.path == newNode.path else {
                    throw .directoryMoveBetweenPartitions
                }
                return try await newNode.contents(of: self).directoryLayer.move(
                    oldNode.partitionSubpath, to: newNode.partitionSubpath, in: tr
                )
            }

            if newNode.exists {
                throw .directoryAlreadyExists
            }

            guard let parent = try await self.find(tr, Array(newPath.dropLast())).subspace else {
                throw .directoryParentDoesNotExist
            }
            tr.set(key: Self.subdirectoryKey(parent, newPath.last!), value: try self.prefix(ofNode: oldSubspace))
            try await self.removeFromParent(tr, oldPath)
            return try self.contentsOfNode(oldSubspace, path: newPath, layer: oldNode.layer)
        }

        /// Removes the directory at given path, its contents and all subdirectories.
        /// Throws ``FDB/Error/directoryDoesNotExist`` if there is no such directory.
        ///
        /// Clients which already opened the directory might still write into its prefix after it's removed.
        public func remove(_ path: [String], in tr: borrowing Transaction) async throws(FDB.Error) {
            _ = try await self.remove(tr, path, failIfMissing: true)
        }

        /// Removes the directory at given path, its contents and all subdirectories, if it exists.
        ///
        /// - returns: Whether the directory existed
        @discardableResult
        public func removeIfExists(_ path: [String], in tr: borrowing Transaction) async throws(FDB.Error) -> Bool {
            try await self.remove(tr, path, failIfMissing: false)
        }

        /// Names of subdirectories of the directory at given path (the root directory by default)
        public func list(
            _ path: [String] = [],
            snapshot: Bool = false,
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> [String] {
            try await self.checkVersion(tr, writeAccess: false, snapshot: snapshot)

            let node = try await self.find(tr, path, snapshot: snapshot).prefetched(tr, snapshot: snapshot)
            guard let subspace = node.subspace else {
                throw .directoryDoesNotExist
            }
            if node.isInPartition(includingEmptySubpath: true) {
                return try await node.contents(of: self).directoryLayer.list(
                    node.partitionSubpath, snapshot: snapshot, in: tr
                )
            }
            return try await self.subdirectories(tr, of: subspace, snapshot: snapshot).map(\.name)
        }

        /// Whether a directory exists at given path
        public func exists(
            _ path: [String] = [],
            snapshot: Bool = false,
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> Bool {
            try await self.checkVersion(tr, writeAccess: false, snapshot: snapshot)

            let node = try await self.find(tr, path, snapshot: snapshot).prefetched(tr, snapshot: snapshot)
            guard node.exists else {
                return false
            }
            if node.isInPartition {
                return try await node.contents(of: self).directoryLayer.exists(
                    node.partitionSubpath, snapshot: snapshot, in: tr
                )
            }
            return true
        }

        // MARK: - Implementation

        private func createOrOpen(
            _ tr: borrowing Transaction,
            _ path: [String],
            layer: Bytes?,
            prefix: Bytes?,
            allowCreate: Bool,
            allowOpen: Bool,
            snapshot: Bool = false
        ) async throws(FDB.Error) -> DirectorySubspace {
            try await self.checkVersion(tr, writeAccess: false, snapshot: snapshot)

            if prefix != nil, !self.allowManualPrefixes {
                throw .directoryManualPrefixesDisabled
            }
            if path.isEmpty {
                // The root directory contains the metadata and can't be opened
                throw .directoryRootOperation
            }

            let existingNode = try await self.find(tr, path, snapshot: snapshot).prefetched(tr, snapshot: snapshot)
            if existingNode.exists {
                if existingNode.isInPartition {
                    return try await existingNode.contents(of: self).directoryLayer.createOrOpen(
                        tr,
                        existingNode.partitionSubpath,
                        layer: layer,
                        prefix: prefix,
                        allowCreate: allowCreate,
                        allowOpen: allowOpen,
                        snapshot: snapshot
                    )
                }
                if !allowOpen {
                    throw .directoryAlreadyExists
                }
                if let layer, !layer.isEmpty, existingNode.layer != layer {
                    throw .directoryIncompatibleLayer
                }
                return try existingNode.contents(of: self)
            }

            if !allowCreate {
                throw .directoryDoesNotExist
            }

            try await self.checkVersion(tr, writeAccess: true)

            let newPrefix: Bytes
            if let prefix {
                guard try await self.isPrefixFree(tr, prefix, snapshot: false) else {
                    throw .directoryPrefixInUse
                }
                newPrefix = prefix
            } else {
                newPrefix = self.contentSubspace.prefix + (try await self.allocator.allocate(in: tr))
                if try await !tr.getAll(KeyRange(begin: newPrefix, end: try Self.strinc(newPrefix)), limit: 1).isEmpty {
                    throw .directoryPrefixNotEmpty
                }
                guard try await self.isPrefixFree(tr, newPrefix, snapshot: true) else {
                    throw .directoryPrefixConflict
                }
            }

            let parentNode: Subspace
            if path.count > 1 {
                let parent = try await self.createOrOpen(Array(path.dropLast()), in: tr)
                parentNode = self.node(withPrefix: parent.prefix)
            } else {
                parentNode = self.rootNode
            }

            let node = self.node(withPrefix: newPrefix)
            let layer = layer ?? []
            tr.set(key: Self.subdirectoryKey(parentNode, path.last!), value: newPrefix)
            tr.set(key: Self.layerKey(node), value: layer)

            return try self.contentsOfNode(node, path: path, layer: layer)
        }

        private func remove(
            _ tr: borrowing Transaction,
            _ path: [String],
            failIfMissing: Bool
        ) async throws(FDB.Error) -> Bool {
            try await self.checkVersion(tr, writeAccess: true)

            if path.isEmpty {
                throw .directoryRootOperation
            }

            let node = try await self.find(tr, path).prefetched(tr)
            guard let subspace = node.subspace else {
                if failIfMissing {
                    throw .directoryDoesNotExist
                }
                return false
            }
            if node.isInPartition {
                return try await node.contents(of: self).directoryLayer.remove(
                    tr, node.partitionSubpath, failIfMissing: failIfMissing
                )
            }

            try await self.removeRecursively(tr, subspace)
            try await self.removeFromParent(tr, path)
            return true
        }

        private func checkVersion(
            _ tr: borrowing Transaction,
            writeAccess: Bool,
            snapshot: Bool = false
        ) async throws(FDB.Error) {
            let versionKey = self.rootNode[Self.bytes("version")]
            guard let value = try await tr.get(key: versionKey, snapshot: snapshot).value else {
                if writeAccess {
                    var value = Bytes()
                    for part in [Self.version.major, Self.version.minor, Self.version.patch] {
                        withUnsafeBytes(of: part.littleEndian) { value.append(contentsOf: $0) }
                    }
                    tr.set(key: versionKey, value: value)
                }
                return
            }

            guard value.count == 12 else {
                throw .directoryIncompatibleVersion
            }
            let major = value[0 ..< 4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let minor = value[4 ..< 8].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            if major > Self.version.major {
                throw .directoryIncompatibleVersion
            }
            if minor > Self.version.minor, writeAccess {
                throw .directoryReadOnlyVersion
            }
        }

        /// Finds the node at given path, or the partition containing it, or the first missing node on the path
        private func find(
            _ tr: borrowing Transaction,
            _ path: [String],
            snapshot: Bool = false
        ) async throws(FDB.Error) -> Node {
            var node = Node(subspace: self.rootNode, path: [], targetPath: path)
            for (index, name) in path.enumerated() {
                let prefix = try await tr.get(key: Self.subdirectoryKey(node.subspace!, name), snapshot: snapshot).value
                node = Node(subspace: prefix.map(self.node(withPrefix:)), path: Array(path[...index]), targetPath: path)
                guard node.exists else {
                    return node
                }
                node = try await node.prefetched(tr, snapshot: snapshot)
                if node.layer == Self.partitionLayer {
                    return node
                }
            }
            return node
        }

        private func subdirectories(
            _ tr: borrowing Transaction,
            of node: Subspace,
            snapshot: Bool = false
        ) async throws(FDB.Error) -> [(name: String, node: Subspace)] {
            let subdirectories = node[Self.subdirectories]
            var result: [(name: String, node: Subspace)] = []
            for record in try await tr.getAll(subdirectories.range, snapshot: snapshot) {
                guard case let .string(name) = try subdirectories.unpack(record.key).elements.first else {
                    throw .unpackTypeMismatch
                }
                result.append((name, self.node(withPrefix: record.value)))
            }
            return result
        }

        private func removeFromParent(_ tr: borrowing Transaction, _ path: [String]) async throws(FDB.Error) {
            if let parent = try await self.find(tr, Array(path.dropLast())).subspace {
                tr.clear(key: Self.subdirectoryKey(parent, path.last!))
            }
        }

        private func removeRecursively(_ tr: borrowing Transaction, _ node: Subspace) async throws(FDB.Error) {
            for subdirectory in try await self.subdirectories(tr, of: node) {
                try await self.removeRecursively(tr, subdirectory.node)
            }
            let prefix = try self.prefix(ofNode: node)
            tr.clear(range: KeyRange(begin: prefix, end: try Self.strinc(prefix)))
            tr.clear(range: node.range)
        }

        /// Whether given prefix neither contains nor is contained by any allocated prefix (including the root node)
        private func isPrefixFree(
            _ tr: borrowing Transaction,
            _ prefix: Bytes,
            snapshot: Bool
        ) async throws(FDB.Error) -> Bool {
            if prefix.isEmpty {
                return false
            }
            if try await self.nodeContainingKey(tr, prefix, snapshot: snapshot) != nil {
                return false
            }
            let range = KeyRange(
                begin: self.node(withPrefix: prefix),
                end: self.node(withPrefix: try Self.strinc(prefix))
            )
            return try await tr.getAll(range, limit: 1, snapshot: snapshot).isEmpty
        }

        private func nodeContainingKey(
            _ tr: borrowing Transaction,
            _ key: Bytes,
            snapshot: Bool
        ) async throws(FDB.Error) -> Subspace? {
            if key.starts(with: self.nodeSubspace.prefix) {
                return self.rootNode
            }
            let range = KeyRange(begin: self.nodeSubspace.range.begin, end: self.node(withPrefix: key).prefix + [0x00])
            for record in try await tr.getAll(range, limit: 1, snapshot: snapshot, reverse: true) {
                let previousPrefix = try self.prefix(ofNode: record.key)
                if key.starts(with: previousPrefix) {
                    return self.node(withPrefix: previousPrefix)
                }
            }
            return nil
        }

        func node(withPrefix prefix: Bytes) -> Subspace {
            self.nodeSubspace[prefix]
        }

        private func prefix(ofNode node: some FDB.Key) throws(FDB.Error) -> Bytes {
            guard case let .bytes(prefix) = try self.nodeSubspace.unpack(node).elements.first else {
                throw .unpackTypeMismatch
            }
            return prefix
        }

        fileprivate func contentsOfNode(_ node: Subspace, path: [String], layer: Bytes) throws(FDB.Error) -> DirectorySubspace {
            let prefix = try self.prefix(ofNode: node)
            let path = self.path + path
            if layer == Self.partitionLayer {
                return DirectorySubspace(
                    path: path,
                    layer: layer,
                    prefix: prefix,
                    directoryLayer: DirectoryLayer(
                        nodeSubspace: Subspace(prefix: prefix + [0xFE]),
                        contentSubspace: Subspace(prefix: prefix),
                        allowManualPrefixes: false,
                        path: path
                    ),
                    parentDirectoryLayer: self
                )
            }
            return DirectorySubspace(path: path, layer: layer, prefix: prefix, directoryLayer: self)
        }

        private static func subdirectoryKey(_ node: Subspace, _ name: String) -> Subspace {
            node[Self.subdirectories, name]
        }

        private static func layerKey(_ node: Subspace) -> Subspace {
            node[Self.bytes("layer")]
        }

        private static func bytes(_ string: String) -> Bytes {
            Bytes(string.utf8)
        }

        static func strinc(_ prefix: Bytes) throws(FDB.Error) -> Bytes {
            var prefix = prefix
            while prefix.last == 0xFF {
                prefix.removeLast()
            }
            guard !prefix.isEmpty else {
                throw .directoryInvalidPrefix
            }
            prefix[prefix.count - 1] += 1
            return prefix
        }
    }
}

// MARK: - Node

extension FDB.DirectoryLayer {
    /// A node of the directory tree, as found by a path lookup
    fileprivate struct Node {
        /// Node subspace, `nil` if the node doesn't exist
        let subspace: FDB.Subspace?
        /// Path of this node
        let path: [String]
        /// Path being looked up (longer than ``path`` if the lookup stopped at a partition)
        let targetPath: [String]
        var layer: Bytes = []

        init(subspace: FDB.Subspace?, path: [String], targetPath: [String]) {
            self.subspace = subspace
            self.path = path
            self.targetPath = targetPath
        }

        var exists: Bool {
            self.subspace != nil
        }

        func prefetched(_ tr: borrowing FDB.Transaction, snapshot: Bool = false) async throws(FDB.Error) -> Self {
            guard let subspace = self.subspace else {
                return self
            }
            var node = self
            node.layer = try await tr.get(key: FDB.DirectoryLayer.layerKey(subspace), snapshot: snapshot).value ?? []
            return node
        }

        var isInPartition: Bool {
            self.isInPartition(includingEmptySubpath: false)
        }

        func isInPartition(includingEmptySubpath: Bool) -> Bool {
            self.exists
                && self.layer == FDB.DirectoryLayer.partitionLayer
                && (includingEmptySubpath || self.targetPath.count > self.path.count)
        }

        var partitionSubpath: [String] {
            Array(self.targetPath[self.path.count...])
        }

        func contents(of directoryLayer: FDB.DirectoryLayer) throws(FDB.Error) -> FDB.DirectorySubspace {
            try directoryLayer.contentsOfNode(self.subspace!, path: self.path, layer: self.layer)
        }
    }
}

// MARK: - Database helpers

extension FDB.DirectoryLayer {
    /// Same as ``createOrOpen(_:layer:in:)-(_,_,FDB.Transaction)``, in a separate transaction
    public func createOrOpen(_ path: [String], layer: Bytes? = nil, in db: FDB.Database) async throws -> FDB.DirectorySubspace {
        try await db.withTransaction { tr in try await self.createOrOpen(path, layer: layer, in: tr) }
    }

    /// Same as ``open(_:layer:snapshot:in:)-(_,_,_,FDB.Transaction)``, in a separate transaction
    public func open(_ path: [String], layer: Bytes? = nil, in db: FDB.Database) async throws -> FDB.DirectorySubspace {
        try await db.withTransaction { tr in try await self.open(path, layer: layer, in: tr) }
    }

    /// Same as ``create(_:layer:prefix:in:)-(_,_,_,FDB.Transaction)``, in a separate transaction
    public func create(
        _ path: [String],
        layer: Bytes? = nil,
        prefix: Bytes? = nil,
        in db: FDB.Database
    ) async throws -> FDB.DirectorySubspace {
        try await db.withTransaction { tr in try await self.create(path, layer: layer, prefix: prefix, in: tr) }
    }

    /// Same as ``move(_:to:in:)-(_,_,FDB.Transaction)``, in a separate transaction
    public func move(_ oldPath: [String], to newPath: [String], in db: FDB.Database) async throws -> FDB.DirectorySubspace {
        try await db.withTransaction { tr in try await self.move(oldPath, to: newPath, in: tr) }
    }

    /// Same as ``remove(_:in:)-(_,FDB.Transaction)``, in a separate transaction
    public func remove(_ path: [String], in db: FDB.Database) async throws {
        try await db.withTransaction { tr in try await self.remove(path, in: tr) }
    }

    /// Same as ``removeIfExists(_:in:)-(_,FDB.Transaction)``, in a separate transaction
    @discardableResult
    public func removeIfExists(_ path: [String], in db: FDB.Database) async throws -> Bool {
        try await db.withTransaction { tr in try await self.removeIfExists(path, in: tr) }
    }

    /// Same as ``list(_:snapshot:in:)-(_,_,FDB.Transaction)``, in a separate transaction
    public func list(_ path: [String] = [], in db: FDB.Database) async throws -> [String] {
        try await db.withTransaction { tr in try await self.list(path, in: tr) }
    }

    /// Same as ``exists(_:snapshot:in:)-(_,_,FDB.Transaction)``, in a separate transaction
    public func exists(_ path: [String] = [], in db: FDB.Database) async throws -> Bool {
        try await db.withTransaction { tr in try await self.exists(path, in: tr) }
    }
}
