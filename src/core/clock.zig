//! Clock interface and implementations for time management with testing support.
//! Provides a flexible abstraction over time functions that can be replaced during tests.

const std = @import("std");

/// Clock provides time-related operations with implementations that can be
/// swapped between system time and test-controlled time.
pub const Clock = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    /// Virtual method table for Clock implementations
    pub const VTable = struct {
        /// Get microsecond timestamp
        mcsTimestampFn: *const fn (ptr: *anyopaque) i64,
        /// Get millisecond timestamp
        msTimestampFn: *const fn (ptr: *anyopaque) i64,
        /// Get nanosecond timestamp
        nsTimestampFn: *const fn (ptr: *anyopaque) i128,
        /// Get default timestamp (implementation-specific unit)
        timestampFn: *const fn (ptr: *anyopaque) i64,
        /// Sleep for the given duration in nanoseconds
        sleepFn: *const fn (ptr: *anyopaque, duration: u64) void,
    };

    /// Get current time in microseconds
    pub fn microTimestamp(self: *const Clock) i64 {
        return self.vtable.mcsTimestampFn(self.ptr);
    }

    /// Get current time in milliseconds
    pub fn milliTimestamp(self: *const Clock) i64 {
        return self.vtable.msTimestampFn(self.ptr);
    }

    /// Get current time in nanoseconds
    pub fn nanoTimestamp(self: *const Clock) i128 {
        return self.vtable.nsTimestampFn(self.ptr);
    }

    /// Get current time in implementation-specific units
    pub fn timestamp(self: *const Clock) i64 {
        return self.vtable.timestampFn(self.ptr);
    }

    /// Sleep for the given duration in nanoseconds
    pub fn sleep(self: *const Clock, duration: u64) void {
        self.vtable.sleepFn(self.ptr, duration);
    }
};

/// System clock implementation that uses std.time functions
pub const SystemClock = struct {
    /// Create a new system clock
    pub fn init() SystemClock {
        return .{};
    }

    /// Get interface to this clock implementation
    pub fn clock(self: *SystemClock) Clock {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn mcsTimestampImpl(_: *anyopaque) i64 {
        return @intCast(std.time.microTimestamp());
    }

    fn msTimestampImpl(_: *anyopaque) i64 {
        return @intCast(std.time.milliTimestamp());
    }

    fn nsTimestampImpl(_: *anyopaque) i128 {
        return @intCast(std.time.nanoTimestamp());
    }

    fn timestampImpl(_: *anyopaque) i64 {
        return @intCast(std.time.timestamp());
    }

    fn sleepImpl(_: *anyopaque, duration: u64) void {
        std.Thread.sleep(duration);
    }

    const vtable = Clock.VTable{
        .mcsTimestampFn = mcsTimestampImpl,
        .msTimestampFn = msTimestampImpl,
        .nsTimestampFn = nsTimestampImpl,
        .timestampFn = timestampImpl,
        .sleepFn = sleepImpl,
    };
};

/// Mock clock implementation for testing with controllable time
pub const MockClock = struct {
    current_time_ns: i64,

    /// Create a new mock clock with the specified initial time in nanoseconds
    pub fn init(initial_time_ns: i64) MockClock {
        return .{
            .current_time_ns = initial_time_ns,
        };
    }

    /// Get interface to this clock implementation
    pub fn clock(self: *MockClock) Clock {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Manually advance clock by specified nanoseconds
    pub fn advance(self: *MockClock, duration_ns: i64) void {
        self.current_time_ns += duration_ns;
        if (duration_ns >= 100) {
            std.Thread.sleep(100);
        }
    }

    /// Set absolute time
    pub fn setTime(self: *MockClock, time_ns: i64) void {
        self.current_time_ns = time_ns;

        std.Thread.sleep(100);
    }

    fn mcsTimestampImpl(ptr: *anyopaque) i64 {
        const self = @as(*MockClock, @ptrCast(@alignCast(ptr)));
        return @divTrunc(self.current_time_ns, std.time.ns_per_us); // 1000
    }

    fn msTimestampImpl(ptr: *anyopaque) i64 {
        const self = @as(*MockClock, @ptrCast(@alignCast(ptr)));
        return @divTrunc(self.current_time_ns, std.time.ns_per_ms); // 1000000;
    }

    fn nsTimestampImpl(ptr: *anyopaque) i128 {
        const self = @as(*MockClock, @ptrCast(@alignCast(ptr)));
        return self.current_time_ns;
    }

    fn timestampImpl(ptr: *anyopaque) i64 {
        const self = @as(*MockClock, @ptrCast(@alignCast(ptr)));
        return @divTrunc(self.current_time_ns, std.time.ns_per_s); // 1000000000;
    }

    fn sleepImpl(ptr: *anyopaque, duration: u64) void {
        const self = @as(*MockClock, @ptrCast(@alignCast(ptr)));
        // In mock clock, sleeping just advances the clock
        self.current_time_ns += @intCast(duration);
    }

    const vtable = Clock.VTable{
        .mcsTimestampFn = mcsTimestampImpl,
        .msTimestampFn = msTimestampImpl,
        .nsTimestampFn = nsTimestampImpl,
        .timestampFn = timestampImpl,
        .sleepFn = sleepImpl,
    };
};
