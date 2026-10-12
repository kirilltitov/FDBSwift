import CFDB
import Logging
import Synchronization

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

extension FDB {
    /// FoundationDB client network, a process-wide singleton.
    ///
    /// FoundationDB allows selecting API version and running the network exactly once per process,
    /// and the network can't be restarted after it was stopped. This type enforces these rules: instead of
    /// crashing, misuse results in an ``FDB/Error``.
    ///
    /// Usually you don't need to touch it at all: network is started automatically when the first
    /// ``FDB/Database`` is opened. Use ``setOption(_:)`` to configure the network (TLS, tracing, external
    /// clients, ...) before opening any database.
    public enum Network {
        private enum State {
            case initial
            case apiVersionSelected
            case running(pthread_t)
            case stopped
        }

        private static let state = Mutex<State>(.initial)
        private static let logger = Logger(label: "FDB.Network")

        /// Sets a network option. Must be called before the network is started (i.e. before opening any database).
        public static func setOption(_ option: NetworkOption) throws(FDB.Error) {
            try self.state.withLock { (state: inout State) throws(FDB.Error) in
                try self.selectAPIVersionIfNeeded(&state)
                guard case .apiVersionSelected = state else {
                    throw FDB.Error.networkAlreadySetup
                }
                self.logger.debug("Setting network option \(option.redactedDescription)")
                try option.withValue { value throws(FDB.Error) in
                    try fdb_network_set_option(option.code, value.baseAddress, Int32(value.count)).check()
                }
            }
        }

        /// Whether the network is currently running
        public static var isRunning: Bool {
            self.state.withLock {
                if case .running = $0 { true } else { false }
            }
        }

        /// Starts the network on a dedicated thread. Does nothing if it's already running.
        public static func start() throws(FDB.Error) {
            try self.state.withLock { (state: inout State) throws(FDB.Error) in
                try self.selectAPIVersionIfNeeded(&state)
                switch state {
                case .running:
                    return
                case .stopped:
                    throw FDB.Error.networkStopped
                case .initial, .apiVersionSelected:
                    break
                }

                try fdb_setup_network().check()

                #if canImport(Darwin)
                var thread: pthread_t?
                #else
                var thread = pthread_t()
                #endif
                let result = pthread_create(&thread, nil, { _ in
                    let error = fdb_run_network()
                    if error != 0 {
                        Logger(label: "FDB.Network").critical("Network thread stopped with error \(FDB.Error(code: error))")
                    }
                    return nil
                }, nil)
                guard result == 0 else {
                    self.logger.critical("Could not create network thread: \(result)")
                    throw FDB.Error.platformError
                }

                #if canImport(Darwin)
                state = .running(thread!)
                #else
                state = .running(thread)
                #endif
                self.logger.debug("Network started (API version \(FDB.apiVersion))")
            }
        }

        /// Stops the network and waits for its thread to finish.
        ///
        /// All databases must be released before calling this. Network can't be started again within the same process.
        public static func stop() throws(FDB.Error) {
            let thread: pthread_t? = try self.state.withLock { (state: inout State) throws(FDB.Error) in
                guard case let .running(thread) = state else {
                    if case .stopped = state {
                        return nil
                    }
                    throw FDB.Error.networkNotStarted
                }
                try fdb_stop_network().check()
                state = .stopped
                return thread
            }
            if let thread {
                pthread_join(thread, nil)
                self.logger.debug("Network stopped")
            }
        }

        private static func selectAPIVersionIfNeeded(_ state: inout State) throws(FDB.Error) {
            guard case .initial = state else {
                return
            }
            try fdb_select_api_version_impl(FDB.apiVersion, FDB_API_VERSION).check()
            state = .apiVersionSelected
        }
    }
}
