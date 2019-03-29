import CFDB

public extension FDB {
    enum NetworkOption {
        /// Enables trace output to a file in a directory of the clients choosing
        case traceEnable(directory: String)

        /// Sets the maximum size in bytes of a single trace output file.
        /// This value should be in the range `[0, INT64_MAX]`.
        /// If the value is set to 0, there is no limit on individual file size.
        /// The default is a maximum size of 10,485,760 bytes.
        case traceRollSize(size: Int64)

        /// Sets the maximum size of all the trace output files put together.
        /// This value should be in the range `[0, INT64_MAX]`. If the value is set to 0, there is no limit on the total
        /// size of the files. The default is a maximum size of 104,857,600 bytes. If the default roll size is used,
        /// this means that a maximum of 10 trace files will be written at a time.
        case traceMaxLogsSize(size: Int64)

        /// Sets the 'LogGroup' attribute with the specified value for all events in the trace output files.
        /// The default log group is 'default'.
        case traceLogGroup(name: String)

        /// Set internal tuning or debugging knobs
        case knob(key: String, value: String)

        /// Set the certificate chain
        case TLSCertBytes(bytes: Bytes)

        /// Set the file from which to load the certificate chain
        case TLSCertPath(path: String)

        /// Set the private key corresponding to your own certificate
        case TLSKeyBytes(bytes: Bytes)

        /// Set the file from which to load the private key corresponding to your own certificate
        case TLSKeyPath(path: String)

        /// Set the ca bundle
        case TLSVerifyPeers(bytes: Bytes)

        /// Set the file from which to load the certificate authority bundle
        case TLSCABytes(bytes: Bytes)

        /// Set the passphrase for encrypted private key. Password should be set before setting the key
        /// for the password to be used.
        case TLSCAPath(path: String)

        /// Set the peer certificate field verification criteria
        case TLSPassword(password: String)

        /// Not documented
        case buggifyEnable

        /// Not documented
        case buggifyDisable

        /// Set the probability of a BUGGIFY section being active for the current execution.
        /// Only applies to code paths first traversed AFTER this option is changed.
        case buggifySectionActivatedProbability(probability: Int64)

        /// Set the probability of an active BUGGIFY section being fired
        case buggifySectionFiredProbability(probability: Int64)

        /// Disables the multi-version client API and instead uses the local client directly.
        /// Must be set before setting up the network.
        case disableMultiVersionClientAPI

        /// If set, callbacks from external client libraries can be called from threads created by
        /// the FoundationDB client library. Otherwise, callbacks will be called from either the thread used to the
        /// callback or the network thread. Setting this option can improve performance when connected using an external
        /// client, but may not be safe to use in all environments. Must be set before setting up the network.
        /// WARNING: This feature is considered experimental at this time.
        case callbacksOnExternalThreads

        /// Adds an external client library for use by the multi-version client API.
        /// Must be set before setting up the network.
        case externalClientLibrary(path: String)

        /// Searches the specified path for dynamic libraries and adds them to the list of client libraries for use
        /// by the multi-version client API. Must be set before setting up the network.
        case externalClientDirectory(directory: String)

        /// Prevents connections through the local client, allowing only connections through externally loaded
        /// client libraries. Intended primarily for testing.
        case disableLocalClient

        /// Disables logging of client statistics, such as sampled transaction activity.
        case disableClientStatisticsLogging

        /// Enables debugging feature to perform slow task profiling. Requires trace logging to be enabled.
        /// WARNING: this feature is not recommended for use in production.
        case enableSlowTaskProfiling

        internal func setOption() throws {
            let internalOption: FDBNetworkOption
            var param: UnsafePointer<Byte>?
            var length: Int32 = 0

            switch self {
            case let .traceEnable(directory):
                FDB.OptionsHelper.stringOptionToPointer(string: directory, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_TRACE_ENABLE
            case let .traceRollSize(size):
                param = getPtr(size)
                length = 8
                internalOption = FDB_NET_OPTION_TRACE_ROLL_SIZE
            case let .traceMaxLogsSize(size):
                param = getPtr(size)
                length = 8
                internalOption = FDB_NET_OPTION_TRACE_MAX_LOGS_SIZE
            case let .traceLogGroup(name):
                FDB.OptionsHelper.stringOptionToPointer(string: name, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_TRACE_LOG_GROUP
            case let .knob(key, value):
                FDB.OptionsHelper.stringOptionToPointer(string: "\(key)=\(value)", pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_KNOB
            case let .TLSCertBytes(bytes):
                FDB.OptionsHelper.bytesOptionToPointer(bytes: bytes, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_TLS_CERT_BYTES
            case let .TLSCertPath(path):
                FDB.OptionsHelper.stringOptionToPointer(string: path, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_TLS_CERT_PATH
            case let .TLSKeyBytes(bytes):
                FDB.OptionsHelper.bytesOptionToPointer(bytes: bytes, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_TLS_KEY_BYTES
            case let .TLSKeyPath(path):
                FDB.OptionsHelper.stringOptionToPointer(string: path, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_TLS_KEY_PATH
            case let .TLSVerifyPeers(bytes):
                FDB.OptionsHelper.bytesOptionToPointer(bytes: bytes, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_TLS_VERIFY_PEERS
            case let .TLSCABytes(bytes):
                FDB.OptionsHelper.bytesOptionToPointer(bytes: bytes, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_TLS_CA_BYTES
            case let .TLSCAPath(path):
                FDB.OptionsHelper.stringOptionToPointer(string: path, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_TLS_CA_PATH
            case let .TLSPassword(password):
                FDB.OptionsHelper.stringOptionToPointer(string: password, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_TLS_PASSWORD
            case .buggifyEnable:
                internalOption = FDB_NET_OPTION_BUGGIFY_ENABLE
            case .buggifyDisable:
                internalOption = FDB_NET_OPTION_BUGGIFY_DISABLE
            case let .buggifySectionActivatedProbability(probability):
                param = getPtr(probability)
                length = 8
                internalOption = FDB_NET_OPTION_BUGGIFY_SECTION_ACTIVATED_PROBABILITY
            case let .buggifySectionFiredProbability(probability):
                param = getPtr(probability)
                length = 8
                internalOption = FDB_NET_OPTION_BUGGIFY_SECTION_FIRED_PROBABILITY
            case .disableMultiVersionClientAPI:
                internalOption = FDB_NET_OPTION_DISABLE_MULTI_VERSION_CLIENT_API
            case .callbacksOnExternalThreads:
                internalOption = FDB_NET_OPTION_CALLBACKS_ON_EXTERNAL_THREADS
            case let .externalClientLibrary(path):
                FDB.OptionsHelper.stringOptionToPointer(string: path, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_EXTERNAL_CLIENT_LIBRARY
            case let .externalClientDirectory(directory):
                FDB.OptionsHelper.stringOptionToPointer(string: directory, pointer: &param, length: &length)
                internalOption = FDB_NET_OPTION_EXTERNAL_CLIENT_DIRECTORY
            case .disableLocalClient:
                internalOption = FDB_NET_OPTION_DISABLE_LOCAL_CLIENT
            case .disableClientStatisticsLogging:
                internalOption = FDB_NET_OPTION_DISABLE_CLIENT_STATISTICS_LOGGING
            case .enableSlowTaskProfiling:
                internalOption = FDB_NET_OPTION_ENABLE_SLOW_TASK_PROFILING
            }

            try fdb_network_set_option(internalOption, param, length).orThrow()
        }
    }

    /// Sets a network option
    /// Warning: options must be set before connection. Otherwise behaviour is undefined.
    ///
    /// - parameters:
    ///   - option: Network option
    /// - returns: current FDB instance (`self`)
    func setOption(_ option: FDB.NetworkOption) throws -> FDB {
        FDB.logger.debug("Trying to set network option \(option)")

        try option.setOption()

        return self
    }
}
