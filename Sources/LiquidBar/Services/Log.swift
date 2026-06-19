import os

enum Log {
    static let app = Logger(subsystem: "com.liquidbar", category: "app")
    static let config = Logger(subsystem: "com.liquidbar", category: "config")
    static let window = Logger(subsystem: "com.liquidbar", category: "window")
    static let ui = Logger(subsystem: "com.liquidbar", category: "ui")
    static let event = Logger(subsystem: "com.liquidbar", category: "event")
    static let spaces = Logger(subsystem: "com.liquidbar", category: "spaces")
    static let plugins = Logger(subsystem: "com.liquidbar", category: "plugins")
    static let memory = Logger(subsystem: "com.liquidbar", category: "memory")
    static let ax = Logger(subsystem: "com.liquidbar", category: "ax")
    static let metal = Logger(subsystem: "com.liquidbar", category: "metal")
    static let perf = Logger(subsystem: "com.liquidbar", category: "perf")
}
