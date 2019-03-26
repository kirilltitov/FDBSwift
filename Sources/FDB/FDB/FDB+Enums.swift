public extension FDB {
    /// Range get streaming mode
    enum StreamingMode: Int32 {
        /// Client intends to consume the entire range and would like it all transferred as early as possible.
        ///
        /// aka `FDB_STREAMING_MODE_WANT_ALL`
        case wantAll = -2

        /// The default. The client doesn't know how much of the range it is likely to used and wants different
        /// performance concerns to be balanced. Only a small portion of data is transferred to the client initially
        /// (in order to minimize costs if the client doesn't read the entire range), and as the caller iterates over
        /// more items in the range larger batches will be transferred in order to minimize latency.
        ///
        /// aka `FDB_STREAMING_MODE_ITERATOR`
        case iterator = -1

        /// Infrequently used. The client has passed a specific row limit and wants that many rows delivered in
        /// a single batch. Because of iterator operation in client drivers make request batches transparent to
        /// the user, consider ``WANT_ALL`` StreamingMode instead. A row limit must be specified if this mode is used.
        ///
        /// aka `FDB_STREAMING_MODE_EXACT`
        case exact = 0

        /// Infrequently used. Transfer data in batches small enough to not be much more expensive than reading
        /// individual rows, to minimize cost if iteration stops early.
        ///
        /// aka `FDB_STREAMING_MODE_SMALL`
        case small = 1

        /// Infrequently used. Transfer data in batches sized in between small and large.
        ///
        /// aka `FDB_STREAMING_MODE_MEDIUM`
        case medium = 2

        /// Infrequently used. Transfer data in batches large enough to be, in a high-concurrency environment,
        /// nearly as efficient as possible. If the client stops iteration early, some disk and network bandwidth
        /// may be wasted. The batch size may still be too small to allow a single client to get high throughput from
        /// the database, so if that is what you need consider the SERIAL StreamingMode.
        ///
        /// aka `FDB_STREAMING_MODE_LARGE`
        case large = 3

        /// Transfer data in batches large enough that an individual client can get reasonable read bandwidth from
        /// the database. If the client stops iteration early, considerable disk and network bandwidth may be wasted.
        ///
        /// aka `FDB_STREAMING_MODE_SERIAL`
        case serial = 4
    }

    enum MutationType: UInt32 {
        /// Performs an addition of little-endian integers. If the existing value in the database is not present or
        /// shorter than ``param``, it is first extended to the length of ``param`` with zero bytes.  If ``param``
        /// is shorter than the existing value in the database, the existing value is truncated to match the length
        /// of ``param``. The integers to be added must be stored in a little-endian representation.
        /// They can be signed in two's complement representation or unsigned. You can add to an integer at a known
        /// offset in the value by prepending the appropriate number of zero bytes to ``param`` and padding with zero
        /// bytes to match the length of the value. However, this offset technique requires that you know the addition
        /// will not cause the integer field within the value to overflow.
        ///
        /// aka `FDB_MUTATION_TYPE_ADD`
        case add = 2

        /// Performs a bitwise ``and`` operation.  If the existing value in the database is not present, then ``param``
        /// is stored in the database. If the existing value in the database is shorter than ``param``, it is first
        /// extended to the length of ``param`` with zero bytes.  If ``param`` is shorter than the existing value in
        /// the database, the existing value is truncated to match the length of ``param``.
        ///
        /// aka `FDB_MUTATION_TYPE_BIT_AND`
        case bitAnd = 6

        /// Performs a bitwise ``or`` operation.  If the existing value in the database is not present or shorter than
        /// ``param``, it is first extended to the length of ``param`` with zero bytes.  If ``param`` is shorter than
        /// the existing value in the database, the existing value is truncated to match the length of ``param``.
        ///
        /// aka `FDB_MUTATION_TYPE_BIT_OR`
        case bitOr = 7

        /// Performs a bitwise ``xor`` operation.  If the existing value in the database is not present or shorter than
        /// ``param``, it is first extended to the length of ``param`` with zero bytes.  If ``param`` is shorter than
        /// the existing value in the database, the existing value is truncated to match the length of ``param``.
        ///
        /// aka `FDB_MUTATION_TYPE_BIT_XOR`
        case bitXor = 8

        /// Appends ``param`` to the end of the existing value already in the database at the given key (or creates the
        /// key and sets the value to ``param`` if the key is empty). This will only append the value if the final
        /// concatenated value size is less than or equal to the maximum value size (i.e., if it fits).
        /// WARNING: No error is surfaced back to the user if the final value is too large because the mutation
        /// will not be applied until after the transaction has been committed. Therefore, it is only safe to use this
        /// mutation type if one can guarantee that one will keep the total value size under the maximum size.
        ///
        /// aka `FDB_MUTATION_TYPE_APPEND_IF_FITS`
        case appendIfFits = 9

        /// Performs a little-endian comparison of byte strings. If the existing value in the database is not present
        /// or shorter than ``param``, it is first extended to the length of ``param`` with zero bytes.  If ``param``
        /// is shorter than the existing value in the database, the existing value is truncated to match the length of
        /// ``param``. The larger of the two values is then stored in the database.
        ///
        /// aka `FDB_MUTATION_TYPE_MAX`
        case max = 12

        /// Performs a little-endian comparison of byte strings. If the existing value in the database is not present,
        /// then ``param`` is stored in the database. If the existing value in the database is shorter than ``param``,
        /// it is first extended to the length of ``param`` with zero bytes.  If ``param`` is shorter than the existing
        /// value in the database, the existing value is truncated to match the length of ``param``.
        /// The smaller of the two values is then stored in the database.
        ///
        /// aka `FDB_MUTATION_TYPE_MIN`
        case min = 13

        /// Transforms ``key`` using a versionstamp for the transaction. Sets the transformed key in the database to
        /// ``param``. The key is transformed by removing the final four bytes from the key and reading those as
        /// a little-Endian 32-bit integer to get a position ``pos``.
        /// The 10 bytes of the key from ``pos`` to ``pos + 10`` are replaced with the versionstamp of
        /// the transaction used. The first byte of the key is position 0. A versionstamp is a 10 byte, unique,
        /// monotonically (but not sequentially) increasing value for each committed transaction. The first 8 bytes are
        /// the committed version of the database (serialized in big-Endian order). The last 2 bytes are monotonic in
        /// the serialization order for transactions. WARNING: At this time, versionstamps are compatible with the Tuple
        /// layer only in the Java and Python bindings. Also, note that prior to API version 520, the offset was
        /// computed from only the final two bytes rather than the final four bytes.
        ///
        /// aka `FDB_MUTATION_TYPE_SET_VERSIONSTAMPED_KEY`
        case setVersionstampedKey = 14

        /// Transforms ``param`` using a versionstamp for the transaction. Sets the ``key`` given to the transformed
        /// ``param``. The parameter is transformed by removing the final four bytes from ``param`` and reading those
        /// as a little-Endian 32-bit integer to get a position ``pos``. The 10 bytes of the parameter
        /// from ``pos`` to ``pos + 10`` are replaced with the versionstamp of the transaction used.
        /// The first byte of the parameter is position 0. A versionstamp is a 10 byte, unique, monotonically
        /// (but not sequentially) increasing value for each committed transaction. The first 8 bytes are the committed
        /// version of the database (serialized in big-Endian order). The last 2 bytes are monotonic in
        /// the serialization order for transactions. WARNING: At this time, versionstamps are compatible with the Tuple
        /// layer only in the Java and Python bindings. Also, note that prior to API version 520, the versionstamp was
        /// always placed at the beginning of the parameter rather than computing an offset.
        ///
        /// aka `FDB_MUTATION_TYPE_SET_VERSIONSTAMPED_VALUE`
        case setVersionstampedValue = 15

        /// Performs lexicographic comparison of byte strings. If the existing value in the database is not present,
        /// then ``param`` is stored. Otherwise the smaller of the two values is then stored in the database.
        ///
        /// aka `FDB_MUTATION_TYPE_BYTE_MIN`
        case byteMin = 16

        /// Performs lexicographic comparison of byte strings. If the existing value in the database is not present,
        /// then ``param`` is stored. Otherwise the larger of the two values is then stored in the database.
        ///
        /// aka `FDB_MUTATION_TYPE_BYTE_MAX`
        case byteMax = 17
    }
}
