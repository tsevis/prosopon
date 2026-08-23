import Foundation

enum Diagnostics {
    /// This process's resident size in MB, reported only when `PROSOPON_MEMORY` is set.
    ///
    /// The stack writer holds a couple of full-canvas pixel buffers at a time and its
    /// footprint settles rather than growing with the layer count. That is worth being
    /// able to confirm on a real corpus, given the documents involved run to gigabytes.
    static var residentMegabytes: Int? {
        guard ProcessInfo.processInfo.environment["PROSOPON_MEMORY"] != nil else { return nil }
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) / (1 << 20) : nil
    }
}
