extension FDB {
    /// An ordered sequence of typed elements encoded with the
    /// [tuple layer](https://github.com/apple/foundationdb/blob/main/design/tuple.md),
    /// mostly used to build keys whose byte order matches the order of their elements.
    ///
    /// ```swift
    /// let key = FDB.Tuple("users", userID, "email")
    /// let (kind, id) = try FDB.Tuple(packed: bytes).unpack(as: String.self, Int.self)
    /// ```
    ///
    /// Elements are packed into a single buffer as soon as they're added, so a tuple is as cheap to use as a key
    /// as raw bytes.
    public struct Tuple: Sendable, FDB.Key, CustomStringConvertible {
        /// Encoded tuple
        public let packed: Bytes

        let versionstampOffset: Int?
        let versionstampCount: Int

        init(encoder: TupleEncoder) {
            self.packed = encoder.bytes
            self.versionstampOffset = encoder.versionstampOffset
            self.versionstampCount = encoder.versionstampCount
        }

        /// Creates a tuple of given elements
        public init<each T: FDB.TuplePackable>(_ element: repeat each T) {
            var encoder = TupleEncoder()
            repeat (each element).pack(into: &encoder)
            self.init(encoder: encoder)
        }

        /// Creates a tuple of dynamically typed elements
        public init(elements: some Sequence<any FDB.TuplePackable>) {
            var encoder = TupleEncoder()
            for element in elements {
                element.pack(into: &encoder)
            }
            self.init(encoder: encoder)
        }

        /// Decodes a packed tuple, validating it
        public init(packed: Bytes) throws(FDB.Error) {
            var decoder = TupleDecoder(packed)
            var versionstamps = VersionstampInfo()
            while !decoder.isAtEnd {
                try decoder.skipElement(&versionstamps)
            }
            self.packed = packed
            self.versionstampOffset = versionstamps.firstOffset
            self.versionstampCount = versionstamps.count
        }

        /// Creates a tuple from bytes which are known to be a valid packed tuple
        init(validatedPacked packed: Bytes) {
            // Scanning is cheap compared to decoding, and the input is valid, so it can't throw
            try! self.init(packed: packed)
        }

        /// All elements of the tuple
        public var elements: [TupleElement] {
            var decoder = TupleDecoder(self.packed)
            var result: [TupleElement] = []
            while !decoder.isAtEnd {
                // Packed bytes are always valid
                result.append(try! decoder.nextElement())
            }
            return result
        }

        /// Number of elements in the tuple
        public var count: Int {
            self.elements.count
        }

        /// Decodes the tuple into elements of given types:
        ///
        /// ```swift
        /// let (name, age) = try tuple.unpack(as: String.self, Int.self)
        /// ```
        ///
        /// Throws ``FDB/Error/unpackTypeMismatch`` if the number of elements or their types don't match.
        public func unpack<each T: FDB.TupleUnpackable>(as type: repeat (each T).Type) throws(FDB.Error) -> (repeat each T) {
            var decoder = TupleDecoder(self.packed)
            let result = (repeat try decoder.next((each type)))
            guard decoder.isAtEnd else {
                throw .unpackTypeMismatch
            }
            return result
        }

        /// Returns a new tuple with given elements appended
        public func appending<each T: FDB.TuplePackable>(_ element: repeat each T) -> Tuple {
            var encoder = TupleEncoder()
            encoder.bytes = self.packed
            encoder.versionstampOffset = self.versionstampOffset
            encoder.versionstampCount = self.versionstampCount
            repeat (each element).pack(into: &encoder)
            return Tuple(encoder: encoder)
        }

        // MARK: FDB.Key

        public var fdbKey: Bytes {
            self.packed
        }

        public func incompleteVersionstampOffset() throws(FDB.Error) -> Int? {
            guard self.versionstampCount <= 1 else {
                throw .multipleIncompleteVersionstamps
            }
            return self.versionstampOffset
        }

        public var description: String {
            "(" + self.elements.map { "\($0)" }.joined(separator: ", ") + ")"
        }
    }
}

extension FDB.Tuple: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.packed == rhs.packed
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.packed)
    }
}

extension FDB.Tuple: Comparable {
    /// Tuples are ordered the same way as their packed representations (i.e. as keys in the database)
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.packed.lexicographicallyPrecedes(rhs.packed)
    }
}
