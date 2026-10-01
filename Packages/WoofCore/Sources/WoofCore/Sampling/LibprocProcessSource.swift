import Darwin
import os

/// Reads every visible process via libproc. Processes owned by root or other users
/// usually fail `proc_pid_rusage` without privileges and are skipped.
public final class LibprocProcessSource: ProcessSource, @unchecked Sendable {
    private let pathCache = OSAllocatedUnfairLock<[ProcessIdentity: String]>(initialState: [:])
    private let responsibleFn: (@convention(c) (pid_t) -> pid_t)?

    public init() {
        // Undocumented libsystem symbol (what Activity Monitor uses); absent → path-based grouping only.
        typealias Fn = @convention(c) (pid_t) -> pid_t
        let handle = dlopen(nil, RTLD_NOW)
        responsibleFn = dlsym(handle, "responsibility_get_pid_responsible_for_pid")
            .map { unsafeBitCast($0, to: Fn.self) }
    }

    public func snapshot() -> [RawProcess] {
        let pids = Self.allPIDs()
        var result: [RawProcess] = []
        result.reserveCapacity(pids.count)
        var seen = Set<ProcessIdentity>()
        for pid in pids where pid > 0 {
            guard let info = Self.bsdInfo(pid), let usage = Self.rusage(pid) else { continue }
            let identity = ProcessIdentity(
                pid: pid,
                startMicros: UInt64(info.pbi_start_tvsec) * 1_000_000 + UInt64(info.pbi_start_tvusec)
            )
            seen.insert(identity)
            let responsible = responsibleFn?(pid)
            result.append(RawProcess(
                identity: identity,
                ppid: Int32(info.pbi_ppid),
                uid: info.pbi_uid,
                name: Self.name(from: info),
                path: path(for: identity),
                responsiblePID: (responsible ?? -1) > 0 ? responsible : nil,
                cpuTimeNanos: MachTime.nanoseconds(usage.ri_user_time &+ usage.ri_system_time),
                memoryBytes: usage.ri_phys_footprint
            ))
        }
        let live = seen
        pathCache.withLock { cache in cache = cache.filter { live.contains($0.key) } }
        return result
    }

    private func path(for identity: ProcessIdentity) -> String? {
        if let cached = pathCache.withLock({ $0[identity] }) { return cached }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(identity.pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(decoding: buffer.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:)), as: UTF8.self)
        pathCache.withLock { $0[identity] = path }
        return path
    }

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 128)
        let count = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        return Array(pids.prefix(Int(max(count, 0))))
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private static func rusage(_ pid: pid_t) -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return status == 0 ? usage : nil
    }

    private static func name(from info: proc_bsdinfo) -> String {
        withUnsafeBytes(of: info.pbi_name) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
