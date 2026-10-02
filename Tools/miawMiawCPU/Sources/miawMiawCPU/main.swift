import Dispatch
import Foundation
import MiawCore
import os

func monotonicSeconds() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}

func write(_ text: String, to handle: FileHandle = .standardOutput) {
    handle.write(Data(text.utf8))
}

/// A thread-safe boolean that only ever goes from false to true.
final class Flag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var isSet: Bool { state.withLock { $0 } }

    func set() {
        state.withLock { $0 = true }
    }
}

/// One thread per core; each 100 ms slice spins for the pattern's load and sleeps the rest.
final class CPUBurn {
    private let flag = Flag()
    private let group = DispatchGroup()

    /// `runStart` is the run's scheduled start on the `monotonicSeconds` clock, so patterns stay on schedule.
    init(job: CPUJob, runStart: Double) {
        for index in 0..<job.cores {
            group.enter()
            let thread = Thread { [flag, group] in
                Self.burn(job: job, runStart: runStart, flag: flag)
                group.leave()
            }
            thread.name = "miaw-\(index)"
            thread.start()
        }
    }

    private static func burn(job: CPUJob, runStart: Double, flag: Flag) {
        let slice = 0.1
        while !flag.isSet {
            let sliceStart = monotonicSeconds()
            let busy = slice * job.load(at: sliceStart - runStart) / 100
            while monotonicSeconds() - sliceStart < busy {}
            let rest = slice - (monotonicSeconds() - sliceStart)
            if rest > 0 { Thread.sleep(forTimeInterval: rest) }
        }
    }

    func stop() {
        flag.set()
        _ = group.wait(timeout: .now() + 1)
    }
}

/// Touched memory, so it counts in the process's footprint rather than just its address space.
/// Touching multi-GB takes seconds, so it runs on its own thread to keep the main queue's signal
/// sources responsive.
final class MemoryHold {
    // UnsafeMutableRawPointer is not Sendable; the touching thread gets the address instead.
    private let address: UInt
    private let stop = Flag()
    private let touched = Flag()
    private let group = DispatchGroup()

    init?(byteCount: Int) {
        guard let pointer = malloc(byteCount) else { return nil }
        address = UInt(bitPattern: pointer)
        group.enter()
        let thread = Thread { [address, stop, touched, group] in
            let pointer = UnsafeMutableRawPointer(bitPattern: address)!
            for offset in stride(from: 0, to: byteCount, by: 4096) {
                if stop.isSet { break }
                pointer.storeBytes(of: 1, toByteOffset: offset, as: UInt8.self)
            }
            touched.set()
            group.leave()
        }
        thread.name = "miaw-mem"
        thread.start()
    }

    var isAllocating: Bool { !touched.isSet }

    func release() {
        stop.set()
        group.wait()
        free(UnsafeMutableRawPointer(bitPattern: address))
    }
}

@MainActor
final class Runner {
    enum Work {
        case cpu(CPUJob)
        case mem(MemJob)
    }

    private let work: Work
    private let schedule: Schedule
    private let launch = monotonicSeconds()
    private let isTTY = isatty(STDOUT_FILENO) == 1
    private var activeRun: Int?
    private var burn: CPUBurn?
    private var memory: MemoryHold?
    private var lastReport = (key: "", time: -Double.infinity)
    private var sources: [any DispatchSourceProtocol] = []

    init(work: Work) {
        self.work = work
        switch work {
        case .cpu(let job): schedule = job.schedule
        case .mem(let job): schedule = job.schedule
        }
    }

    func start() {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { self.finish(Status.stopped) } }
            source.resume()
            sources.append(source)
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
        timer.setEventHandler { MainActor.assumeIsolated { self.tick() } }
        timer.resume()
        sources.append(timer)
    }

    private func tick() {
        let now = monotonicSeconds()
        let phase = schedule.phase(at: now - launch)
        if case .running(let run, _, _) = phase {
            if activeRun != run {
                unload()
                load(run: run)
            }
        } else {
            unload()
        }
        if phase == .finished { finish(Status.done) }
        report(phase, now: now)
    }

    private func load(run: Int) {
        activeRun = run
        switch work {
        case .cpu(let job):
            burn = CPUBurn(job: job, runStart: launch + Double(schedule.start(ofRun: run)))
        case .mem(let job):
            guard let hold = MemoryHold(byteCount: job.byteCount) else {
                write("miawMiawCPU: could not allocate \(job.gigabytes) GB\n", to: .standardError)
                exit(1)
            }
            memory = hold
        }
    }

    private func unload() {
        burn?.stop()
        burn = nil
        memory?.release()
        memory = nil
        activeRun = nil
    }

    /// A TTY gets one self-overwriting line per second; a pipe or log gets a line per phase change or every 10 s.
    private func report(_ phase: Phase, now: Double) {
        let key: String
        switch phase {
        case .waiting: key = "waiting"
        case .running(let run, _, _): key = "run \(run)" + (memory?.isAllocating == true ? " allocating" : "")
        case .napping: key = "napping"
        case .finished: key = "finished"
        }
        let interval = isTTY ? 1.0 : 10.0
        guard key != lastReport.key || now - lastReport.time >= interval else { return }
        lastReport = (key, now)

        let line: String
        switch work {
        case .cpu(let job): line = Status.line(for: phase, cpu: job)
        case .mem(let job): line = Status.line(for: phase, mem: job, allocating: memory?.isAllocating == true)
        }
        write(isTTY ? "\r\u{1B}[K" + line : line + "\n")
    }

    private func finish(_ message: String) -> Never {
        unload()
        write(isTTY ? "\r\u{1B}[K" + message + "\n" : message + "\n")
        exit(0)
    }
}

let command: Command
do {
    command = try ArgumentParser.parse(Array(CommandLine.arguments.dropFirst()),
                                       activeCores: ProcessInfo.processInfo.activeProcessorCount)
} catch {
    write("miawMiawCPU: \(error.message)\n\n\(Usage.text)\n", to: .standardError)
    exit(2)
}

let runner: Runner
switch command {
case .help:
    write(Usage.text + "\n")
    exit(0)
case .cpu(let job):
    runner = Runner(work: .cpu(job))
case .mem(let job):
    runner = Runner(work: .mem(job))
}
runner.start()
// Not dispatchMain(): that drains the main queue off the main thread, which breaks MainActor.assumeIsolated.
RunLoop.main.run()
