extension FDB {
    /// An opened directory: its path, layer and the subspace of its contents.
    ///
    /// Also offers the directory operations with paths relative to this directory.
    ///
    /// Directories created with ``FDB/DirectoryLayer/partitionLayer`` are partitions: their contents are managed by
    /// their own directory layer, so the partition root can't be used as a subspace (``subspace`` throws).
    public struct DirectorySubspace: Hashable, Sendable, CustomStringConvertible {
        /// Absolute path of the directory
        public let path: [String]
        /// Layer the directory was created with (empty by default)
        public let layer: Bytes
        /// Physical prefix of the directory contents
        public let prefix: Bytes

        /// Directory layer managing subdirectories of this directory (a separate one for partitions)
        let directoryLayer: DirectoryLayer
        /// For partitions: directory layer the partition itself belongs to
        let parentDirectoryLayer: DirectoryLayer?

        init(path: [String], layer: Bytes, prefix: Bytes, directoryLayer: DirectoryLayer, parentDirectoryLayer: DirectoryLayer? = nil) {
            self.path = path
            self.layer = layer
            self.prefix = prefix
            self.directoryLayer = directoryLayer
            self.parentDirectoryLayer = parentDirectoryLayer
        }

        /// Whether this directory is a partition
        public var isPartition: Bool {
            self.parentDirectoryLayer != nil
        }

        /// Subspace of the directory contents.
        ///
        /// Throws ``FDB/Error/directoryPartitionRoot`` for partitions: keys can be stored only in their subdirectories.
        public var subspace: Subspace {
            get throws(FDB.Error) {
                guard !self.isPartition else {
                    throw .directoryPartitionRoot
                }
                return Subspace(prefix: self.prefix)
            }
        }

        public var description: String {
            "DirectorySubspace(path: \(self.path), prefix: \(self.prefix))"
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.path == rhs.path && lhs.layer == rhs.layer && lhs.prefix == rhs.prefix
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.path)
            hasher.combine(self.prefix)
        }

        // MARK: - Directory operations (paths are relative to this directory)

        /// Opens or creates a subdirectory, see ``FDB/DirectoryLayer/createOrOpen(_:layer:in:)-(_,_,FDB.Transaction)``
        public func createOrOpen(
            _ path: [String],
            layer: Bytes? = nil,
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> DirectorySubspace {
            try await self.directoryLayer.createOrOpen(self.subpath(path), layer: layer, in: tr)
        }

        /// Opens a subdirectory, see ``FDB/DirectoryLayer/open(_:layer:snapshot:in:)-(_,_,_,FDB.Transaction)``
        public func open(
            _ path: [String],
            layer: Bytes? = nil,
            snapshot: Bool = false,
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> DirectorySubspace {
            try await self.directoryLayer.open(self.subpath(path), layer: layer, snapshot: snapshot, in: tr)
        }

        /// Creates a subdirectory, see ``FDB/DirectoryLayer/create(_:layer:prefix:in:)-(_,_,_,FDB.Transaction)``
        public func create(
            _ path: [String],
            layer: Bytes? = nil,
            prefix: Bytes? = nil,
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> DirectorySubspace {
            try await self.directoryLayer.create(self.subpath(path), layer: layer, prefix: prefix, in: tr)
        }

        /// Moves a subdirectory, see ``FDB/DirectoryLayer/move(_:to:in:)-(_,_,FDB.Transaction)``
        public func move(
            _ oldPath: [String],
            to newPath: [String],
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> DirectorySubspace {
            try await self.directoryLayer.move(self.subpath(oldPath), to: self.subpath(newPath), in: tr)
        }

        /// Moves this directory to given absolute path (within the same partition)
        public func move(to newAbsolutePath: [String], in tr: borrowing Transaction) async throws(FDB.Error) -> DirectorySubspace {
            let directoryLayer = self.layerForPath([])
            guard newAbsolutePath.starts(with: directoryLayer.path) else {
                throw .directoryMoveBetweenPartitions
            }
            let partitionLength = directoryLayer.path.count
            return try await directoryLayer.move(
                Array(self.path[partitionLength...]),
                to: Array(newAbsolutePath[partitionLength...]),
                in: tr
            )
        }

        /// Removes this directory or its subdirectory, see ``FDB/DirectoryLayer/remove(_:in:)-(_,FDB.Transaction)``
        public func remove(_ path: [String] = [], in tr: borrowing Transaction) async throws(FDB.Error) {
            let directoryLayer = self.layerForPath(path)
            try await directoryLayer.remove(self.subpath(path, of: directoryLayer), in: tr)
        }

        /// Removes this directory or its subdirectory if it exists,
        /// see ``FDB/DirectoryLayer/removeIfExists(_:in:)-(_,FDB.Transaction)``
        @discardableResult
        public func removeIfExists(_ path: [String] = [], in tr: borrowing Transaction) async throws(FDB.Error) -> Bool {
            let directoryLayer = self.layerForPath(path)
            return try await directoryLayer.removeIfExists(self.subpath(path, of: directoryLayer), in: tr)
        }

        /// Names of subdirectories of this directory or its subdirectory
        public func list(
            _ path: [String] = [],
            snapshot: Bool = false,
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> [String] {
            try await self.directoryLayer.list(self.subpath(path), snapshot: snapshot, in: tr)
        }

        /// Whether this directory or its subdirectory exists
        public func exists(
            _ path: [String] = [],
            snapshot: Bool = false,
            in tr: borrowing Transaction
        ) async throws(FDB.Error) -> Bool {
            let directoryLayer = self.layerForPath(path)
            return try await directoryLayer.exists(self.subpath(path, of: directoryLayer), snapshot: snapshot, in: tr)
        }

        // MARK: Implementation

        /// The partition itself (empty path) is managed by its parent directory layer
        private func layerForPath(_ path: [String]) -> DirectoryLayer {
            if path.isEmpty, let parent = self.parentDirectoryLayer {
                return parent
            }
            return self.directoryLayer
        }

        private func subpath(_ path: [String], of directoryLayer: DirectoryLayer? = nil) -> [String] {
            let directoryLayer = directoryLayer ?? self.directoryLayer
            return Array(self.path[directoryLayer.path.count...]) + path
        }
    }
}
