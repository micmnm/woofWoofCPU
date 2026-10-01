import Darwin

/// rusage CPU times are Mach absolute ticks, not nanoseconds; on Apple Silicon the timebase is 125/3.
public enum MachTime {
    public static func nanoseconds(_ ticks: UInt64, numer: UInt32, denom: UInt32) -> UInt64 {
        let product = ticks.multipliedFullWidth(by: UInt64(numer))
        return UInt64(denom).dividingFullWidth(product).quotient
    }

    public static let timebase: (numer: UInt32, denom: UInt32) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (info.numer, info.denom)
    }()

    public static func nanoseconds(_ ticks: UInt64) -> UInt64 {
        nanoseconds(ticks, numer: timebase.numer, denom: timebase.denom)
    }
}
