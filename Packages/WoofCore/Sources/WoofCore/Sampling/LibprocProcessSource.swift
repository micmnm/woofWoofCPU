import Darwin
import os

/// Reads the current user's processes via libproc (spec §4.1: other users' and root's
/// processes fail `proc_pid_rusage` without privileges, so they are skipped up front).
public final class LibprocProcessSource: ProcessSource, @unchecked Sendable {
    private struct Lookup {
        let path: String
        let responsiblePID: Int32?
    }

    /// Path and responsible PID never change for a process identity, so they are read once.
    private let cache = OSAllocatedUnfairLock<[ProcessIdentity: Lookup]>(initialState: [:])
    private let responsibleFn: (@convention(c) (pid_t) -> pid_t)?
    private let uid = getuid()

    public init() {
        // Undocumented libsystem symbol (what Activity Monitor uses); absent → path-based grouping only.
        typealias Fn = @convention(c) (pid_t) -> pid_t
        let handle = dlopen(nil, RTLD_NOW)
        responsibleFn = dlsym(handle, "responsibility_get_pid_responsible_for_pid")
            .map { unsafeBitCast($0, to: Fn.self) }
    }

    public func snapshot() -> [RawProcess] {
        let pids = Self.allPIDs()
        let previous = cache.withLock { $0 }
        var next: [ProcessIdentity: Lookup] = [:]
        next.reserveCapacity(previous.count)
        var result: [RawProcess] = []
        result.reserveCapacity(pids.count)
        for pid in pids where pid > 0 {
            guard let info = Self.bsdInfo(pid), info.pbi_uid == uid, let usage = Self.rusage(pid) else { continue }
            let identity = ProcessIdentity(
                pid: pid,
                startMicros: UInt64(info.pbi_start_tvsec) * 1_000_000 + UInt64(info.pbi_start_tvusec)
            )
            let lookup = previous[identity] ?? lookUp(identity)
            next[identity] = lookup
            result.append(RawProcess(
                identity: identity,
                ppid: Int32(info.pbi_ppid),
                uid: info.pbi_uid,
                name: Self.name(from: info),
                path: lookup?.path,
                responsiblePID: lookup?.responsiblePID,
                cpuTimeNanos: MachTime.nanoseconds(usage.ri_user_time &+ usage.ri_system_time),
                memoryBytes: usage.ri_phys_footprint
            ))
        }
        let live = next
        cache.withLock { $0 = live }
        return result
    }

    /// Nil (and retried next tick) when the path can't be read. The responsible PID is only
    /// needed to group bundled code, so other processes skip that call.
    private func lookUp(_ identity: ProcessIdentity) -> Lookup? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(identity.pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(decoding: buffer.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:)), as: UTF8.self)
        var responsible: Int32?
        if path.contains(".app/") || path.contains(".xpc/"), let pid = responsibleFn?(identity.pid), pid > 0 {
            responsible = pid
        }
        return Lookup(path: path, responsiblePID: responsible)
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
