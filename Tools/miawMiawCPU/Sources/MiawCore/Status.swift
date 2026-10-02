import Foundation

/// The one-line status miawMiawCPU prints while it works.
public enum Status {
    public static let done = "🐱 miaw — done"
    public static let stopped = "🐱 miaw — stopped"

    /// `m:ss`, or `h:mm:ss` from an hour up; partial seconds round up so a countdown never shows 0:00 early.
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    public static func line(for phase: Phase, cpu job: CPUJob) -> String {
        line(for: phase, schedule: job.schedule) { elapsed in
            let cores = job.cores == 1 ? "1 core" : "\(job.cores) cores"
            return "\(cores) @ \(Int(job.load(at: elapsed).rounded()))%"
        }
    }

    public static func line(for phase: Phase, mem job: MemJob) -> String {
        line(for: phase, schedule: job.schedule) { _ in
            "holding \(String(format: "%.1f", job.gigabytes)) GB"
        }
    }

    static func line(for phase: Phase, schedule: Schedule, activity: (Double) -> String) -> String {
        switch phase {
        case .waiting(let remaining):
            return "🐱 miaw… starting in \(clock(remaining))"
        case .running(let run, let elapsed, let remaining):
            var parts = [activity(elapsed), "\(clock(remaining)) left"]
            if schedule.every != nil {
                parts.append(schedule.totalRuns.map { "run \(run + 1)/\($0)" } ?? "run \(run + 1)")
            }
            return "🐱 miaw… " + parts.joined(separator: " · ")
        case .napping(let remaining):
            return "🐱 napping… next run in \(clock(remaining))"
        case .finished:
            return done
        }
    }
}
