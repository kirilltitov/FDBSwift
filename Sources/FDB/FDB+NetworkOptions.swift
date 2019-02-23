import CFDB

public extension FDB {
    public enum NetworkOption: UInt32 {
        case traceEnable                        = 30 // FDB_NET_OPTION_TRACE_ENABLE
        case traceRollSize                      = 31 // FDB_NET_OPTION_TRACE_ROLL_SIZE
        case traceMaxLogsSize                   = 32 // FDB_NET_OPTION_TRACE_MAX_LOGS_SIZE
        case traceLogGroup                      = 33 // FDB_NET_OPTION_TRACE_LOG_GROUP
        case knob                               = 40 // FDB_NET_OPTION_KNOB
        case TLSCertBytes                       = 42 // FDB_NET_OPTION_TLS_CERT_BYTES
        case TLSCertPath                        = 43 // FDB_NET_OPTION_TLS_CERT_PATH
        case TLSKeyBytes                        = 45 // FDB_NET_OPTION_TLS_KEY_BYTES
        case TLSKeyPath                         = 46 // FDB_NET_OPTION_TLS_KEY_PATH
        case TLSVerifyPeers                     = 47 // FDB_NET_OPTION_TLS_VERIFY_PEERS
        case TLSCABytes                         = 52 // FDB_NET_OPTION_TLS_CA_BYTES
        case TLSCAPath                          = 53 // FDB_NET_OPTION_TLS_CA_PATH
        case TLSPassword                        = 54 // FDB_NET_OPTION_TLS_PASSWORD
        case buggifyEnable                      = 48 // FDB_NET_OPTION_BUGGIFY_ENABLE
        case buggifyDisable                     = 49 // FDB_NET_OPTION_BUGGIFY_DISABLE
        case buggifySectionActivatedProbability = 50 // FDB_NET_OPTION_BUGGIFY_SECTION_ACTIVATED_PROBABILITY
        case buggifySectionFiredProbability     = 51 // FDB_NET_OPTION_BUGGIFY_SECTION_FIRED_PROBABILITY
        case disableMultiVersionClientAPI       = 60 // FDB_NET_OPTION_DISABLE_MULTI_VERSION_CLIENT_API
        case callbacksOnExternalThreads         = 61 // FDB_NET_OPTION_CALLBACKS_ON_EXTERNAL_THREADS
        case externalClientLibrary              = 62 // FDB_NET_OPTION_EXTERNAL_CLIENT_LIBRARY
        case externalClientDirectory            = 63 // FDB_NET_OPTION_EXTERNAL_CLIENT_DIRECTORY
        case disableLocalClient                 = 64 // FDB_NET_OPTION_DISABLE_LOCAL_CLIENT
        case disableClientStatisticsLogging     = 70 // FDB_NET_OPTION_DISABLE_CLIENT_STATISTICS_LOGGING
        case enableSlowTaskProfiling            = 71 // FDB_NET_OPTION_ENABLE_SLOW_TASK_PROFILING
    }
    
    fileprivate func setOption(
        _ option: FDB.NetworkOption,
        param: UnsafePointer<Byte>! = nil,
        paramLength: Int32 = 0
    ) throws -> FDB {
        if param == nil {
            self.debug("Trying to set network option \(option) (no params)")
        }

        try fdb_network_set_option(FDBNetworkOption(option.rawValue), param, paramLength).orThrow()

        return self
    }

    /// Sets network option with `Int64` param. It is highly suggested to use existing sugar methods for setting
    /// options instead of this one.
    ///
    /// - Parameter option: Option name
    /// - Parameter param: Option value
    /// - Returns: FDB.self
    @discardableResult public func setOption(_ option: FDB.NetworkOption, param int: Int64) throws -> FDB {
        self.debug("Trying to set network option \(option) with int param \(int)")

        return try self.setOption(option, param: getBytes(int))
    }
    
    /// Sets network option with `[UInt8]` param. It is highly suggested to use existing sugar methods for setting
    /// options instead of this one.
    ///
    /// - Parameter option: Option name
    /// - Parameter param: Option value
    /// - Returns: FDB.self
    @discardableResult public func setOption(_ option: FDB.NetworkOption, param bytes: Bytes) throws -> FDB {
        self.debug("Trying to set network option \(option) with bytes param \(bytes)")

        return try self.setOption(
            option,
            param: UnsafePointer<UInt8>(bytes),
            paramLength: Int32(bytes.count)
        )
    }
    
    /// Sets network option with `String` param. It is highly suggested to use existing sugar methods for setting
    /// options instead of this one.
    ///
    /// - Parameter option: Option name
    /// - Parameter param: Option value
    /// - Returns: FDB.self
    @discardableResult public func setOption(_ option: FDB.NetworkOption, param string: String) throws -> FDB {
        self.debug("Trying to set network option \(option) with string param \(string)")

        return try self.setOption(option, param: string.bytes)
    }

    /// Enables trace output to a file in a directory of the clients choosing
    ///
    /// - Parameter directory: (String) path to output directory (or NULL for current working directory)
    /// - Returns: FDB.self
    @discardableResult public func enableTrace(directory: String) throws -> FDB {
        return try self.setOption(.traceEnable, param: directory)
    }
    
    /// Sets the maximum size in bytes of a single trace output file.
    /// This value should be in the range `[0, INT64_MAX]`. If the value is set to 0, there is no limit on individual
    /// file size. The default is a maximum size of 10,485,760 bytes.
    ///
    /// - Parameter size: (Int) max size of a single trace output file
    /// - Returns: FDB.self
    @discardableResult public func setTraceRollSize(size: Int64) throws -> FDB {
        return try self.setOption(.traceRollSize, param: size)
    }
    
    /// Sets the maximum size of all the trace output files put together.
    /// This value should be in the range `[0, INT64_MAX]`. If the value is set to 0, there is no limit on the total
    /// size of the files. The default is a maximum size of 104,857,600 bytes. If the default roll size is used,
    /// this means that a maximum of 10 trace files will be written at a time.
    ///
    /// - Parameter size: (Int) max total size of trace files
    /// - Returns: FDB.self
    @discardableResult public func setTraceMaxLogsSize(size: Int64) throws -> FDB {
        return try self.setOption(.traceMaxLogsSize, param: size)
    }
    
    /// Sets the 'LogGroup' attribute with the specified value for all events in the trace output files.
    /// The default log group is 'default'.
    ///
    /// - Parameter name: (String) value of the LogGroup attribute
    /// - Returns: FDB.self
    @discardableResult public func setTraceLogGroup(name: String) throws -> FDB {
        return try self.setOption(.traceLogGroup, param: name)
    }
    
    /// Set internal tuning or debugging knobs
    ///
    /// - Parameter key: (String) Knob name
    /// - Parameter value: (String) Knob value
    /// - Returns: FDB.self
    @discardableResult public func setKnob(key: String, value: String) throws -> FDB {
        return try self.setOption(.knob, param: "\(key)=\(value)")
    }
    
    /// Set the certificate chain
    ///
    /// - Parameter bytes: (Bytes) certificates
    /// - Returns: FDB.self
    @discardableResult public func setTLSCert(bytes: Bytes) throws -> FDB {
        return try self.setOption(.TLSCertBytes, param: bytes)
    }
    
    /// Set the file from which to load the certificate chain
    ///
    /// - Parameter path: (String) file path
    /// - Returns: FDB.self
    @discardableResult public func setTLSCert(path: String) throws -> FDB {
        return try self.setOption(.TLSCertPath, param: path)
    }
    
    /// Set the private key corresponding to your own certificate
    ///
    /// - Parameter bytes: (Bytes) key
    /// - Returns: FDB.self
    @discardableResult public func setTLSKey(bytes: Bytes) throws -> FDB {
        return try self.setOption(.TLSKeyBytes, param: bytes)
    }
    
    /// Set the file from which to load the private key corresponding to your own certificate
    ///
    /// - Parameter path: (String) file path
    /// - Returns: FDB.self
    @discardableResult public func setTLSKey(path: String) throws -> FDB {
        return try self.setOption(.TLSKeyPath, param: path)
    }
    
    /// Set the ca bundle
    ///
    /// - Parameter pattern: (Bytes) ca bundle
    /// - Returns: FDB.self
    @discardableResult public func setTLSVerifyPeers(pattern bytes: Bytes) throws -> FDB {
        return try self.setOption(.TLSVerifyPeers, param: bytes)
    }
    
    /// Set the file from which to load the certificate authority bundle
    ///
    /// - Parameter bytes: (String) file path
    /// - Returns: FDB.self
    @discardableResult public func setTLSCA(bytes: Bytes) throws -> FDB {
        return try self.setOption(.TLSCABytes, param: bytes)
    }
    
    /// Set the passphrase for encrypted private key. Password should be set before setting the key
    /// for the password to be used.
    ///
    /// - Parameter path: (String) key passphrase
    /// - Returns: FDB.self
    @discardableResult public func setTLSCA(path: String) throws -> FDB {
        return try self.setOption(.TLSCAPath, param: path)
    }
    
    /// Set the peer certificate field verification criteria
    ///
    /// - Parameter password: (Bytes) verification pattern
    /// - Returns: FDB.self
    @discardableResult public func setTLS(password: String) throws -> FDB {
        return try self.setOption(.TLSCAPath, param: password)
    }
    
    /// Not documented
    ///
    /// - Returns: FDB.self
    @discardableResult public func enableBuggify() throws -> FDB {
        return try self.setOption(.buggifyEnable)
    }
    
    /// Not documented
    ///
    /// - Returns: FDB.self
    @discardableResult public func disableBuggify() throws -> FDB {
        return try self.setOption(.buggifyDisable)
    }
    
    /// Set the probability of a BUGGIFY section being active for the current execution.
    /// Only applies to code paths first traversed AFTER this option is changed.
    ///
    /// - Parameter probability: (Int) probability expressed as a percentage between 0 and 100
    /// - Returns: FDB.self
    @discardableResult public func setBuggifyActivated(probability: Int64) throws -> FDB {
        return try self.setOption(.buggifySectionActivatedProbability, param: probability)
    }
    
    /// Set the probability of an active BUGGIFY section being fired
    ///
    /// - Parameter probability: (Int) probability expressed as a percentage between 0 and 100
    /// - Returns: FDB.self
    @discardableResult public func setBuggifyFired(probability: Int64) throws -> FDB {
        return try self.setOption(.buggifySectionFiredProbability, param: probability)
    }
    
    /// Disables the multi-version client API and instead uses the local client directly.
    /// Must be set before setting up the network.
    ///
    /// - Returns: FDB.self
    @discardableResult public func disableMultiVersionClientAPI() throws -> FDB {
        return try self.setOption(.disableMultiVersionClientAPI)
    }
    
    /// If set, callbacks from external client libraries can be called from threads created by
    /// the FoundationDB client library. Otherwise, callbacks will be called from either the thread used to
    /// add the callback or the network thread. Setting this option can improve performance when connected using
    /// an external client, but may not be safe to use in all environments. Must be set before setting up the network.
    /// WARNING: This feature is considered experimental at this time.
    ///
    /// - Returns: FDB.self
    @discardableResult public func executeCallbacksOnExternalThreads() throws -> FDB {
        return try self.setOption(.callbacksOnExternalThreads)
    }
    
    /// Adds an external client library for use by the multi-version client API.
    /// Must be set before setting up the network.
    ///
    /// - Parameter path: (String) path to client library
    /// - Returns: FDB.self
    @discardableResult public func setExternalClientLibrary(path: String) throws -> FDB {
        return try self.setOption(.externalClientLibrary, param: path)
    }
    
    /// Searches the specified path for dynamic libraries and adds them to the list of client libraries for use
    /// by the multi-version client API. Must be set before setting up the network.
    ///
    /// - Parameter directory: (String) path to directory containing client libraries
    /// - Returns: FDB.self
    @discardableResult public func setExternalClientLibrary(directory: String) throws -> FDB {
        return try self.setOption(.externalClientDirectory, param: directory)
    }
    
    /// Prevents connections through the local client, allowing only connections through externally loaded
    /// client libraries. Intended primarily for testing.
    ///
    /// - Returns: FDB.self
    @discardableResult public func disableLocalClient() throws -> FDB {
        return try self.setOption(.disableLocalClient)
    }
    
    /// Disables logging of client statistics, such as sampled transaction activity.
    ///
    /// - Returns: FDB.self
    @discardableResult public func disableClientStatisticsLogging() throws -> FDB {
        return try self.setOption(.disableClientStatisticsLogging)
    }
    
    /// Enables debugging feature to perform slow task profiling. Requires trace logging to be enabled.
    /// WARNING: this feature is not recommended for use in production.
    ///
    /// - Returns: FDB.self
    @discardableResult public func enableSlowTaskProfiling() throws -> FDB {
        return try self.setOption(.enableSlowTaskProfiling)
    }
}
