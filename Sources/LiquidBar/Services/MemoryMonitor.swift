import Darwin

enum MemoryMonitor {
    static let maxRSSBytes = 180 * 1024 * 1024  // 180 MB

    static func getRSSBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size)
    }

    static func checkMemoryHealth(baseline: Int) {
        let current = getRSSBytes()
        if current > maxRSSBytes {
            Log.memory.warning("RSS \(current) exceeds \(maxRSSBytes) ceiling")
        } else if current > baseline * 3 / 2 {
            Log.memory.warning("RSS \(current) grew >50% from baseline \(baseline)")
        } else {
            Log.memory.trace("Memory OK: \(current) bytes")
        }
    }
}
