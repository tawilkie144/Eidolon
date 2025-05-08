//! Tests for the Clock interface and implementations.

const std = @import("std");
const core = @import("Eidolon_core");

const Clock = core.Clock;
const testing = std.testing;
const time = std.time;

// Test SystemClock operations
test "SystemClock basic operations" {
    var system_clock = Clock.SystemClock.init();
    var clock = system_clock.clock();

    // Time should proceed forward
    const timestamp1 = clock.timestamp();
    // Wait a bit to ensure timestamps differ
    time.sleep(10 * time.ns_per_ms);
    const timestamp2 = clock.timestamp();

    try testing.expect(timestamp2 >= timestamp1);

    // Different timestamp units should be related correctly
    const s = clock.timestamp();
    const s_sys = std.time.timestamp();
    const ns = clock.nanoTimestamp();
    const ns_sys = std.time.nanoTimestamp();
    const ms = clock.milliTimestamp();
    const ms_sys = std.time.milliTimestamp();
    const mcs = clock.microTimestamp();
    const mcs_sys = std.time.microTimestamp();

    // Allow for small timing variations during test execution
    const ns_from_ms = ms * time.ns_per_ms;
    const ns_from_mcs = mcs * time.ns_per_us;

    // These relationships should be approximately correct
    // (with some margin for time passing between calls)
    try testing.expect(ns >= ns_from_ms - time.ns_per_s);
    try testing.expect(ns >= ns_from_mcs - time.ns_per_s);

    try testing.expect(s == s_sys);
    try testing.expect(@abs(ns - ns_sys) < 500);
    try testing.expect(@abs(mcs - mcs_sys) < 50);
    try testing.expect(@abs(ms - ms_sys) < 5);
}

// Test MockClock operations and time control
test "MockClock time control" {
    const INITIAL_TIME = 1000 * time.ns_per_s; // Start at 1000 seconds
    var mock_clock = Clock.MockClock.init(INITIAL_TIME);
    var clock = mock_clock.clock();

    // Initial time should match what we set
    try testing.expectEqual(INITIAL_TIME, clock.nanoTimestamp());
    try testing.expectEqual(INITIAL_TIME / time.ns_per_ms, clock.milliTimestamp());
    try testing.expectEqual(INITIAL_TIME / time.ns_per_us, clock.microTimestamp());
    try testing.expectEqual(INITIAL_TIME / time.ns_per_s, clock.timestamp());

    // Time should not change until we tell it to
    try testing.expectEqual(INITIAL_TIME, clock.nanoTimestamp());

    // Advance should move time forward
    const ADVANCE_TIME = 5 * time.ns_per_s; // 5 seconds
    mock_clock.advance(ADVANCE_TIME);

    try testing.expectEqual(INITIAL_TIME + ADVANCE_TIME, clock.nanoTimestamp());

    // setTime should set absolute time
    const NEW_TIME = 2000 * time.ns_per_s; // 2000 seconds
    mock_clock.setTime(NEW_TIME);

    try testing.expectEqual(NEW_TIME, clock.nanoTimestamp());

    // Sleep should advance the mock clock
    const SLEEP_TIME = 3 * time.ns_per_s; // 3 seconds
    clock.sleep(SLEEP_TIME);

    try testing.expectEqual(NEW_TIME + SLEEP_TIME, clock.nanoTimestamp());
}

// Test polymorphic usage of SystemClock and MockClock through the same interface
test "Clock interface polymorphism" {
    // Function that uses a clock interface without knowing implementation
    const tickingFunction = struct {
        fn tick(clock_interface: *const Clock.Clock, ticks: u32) i64 {
            var final_time: i64 = 0;
            const tick_duration = time.ns_per_ms * 100; // 100ms per tick

            var i: u32 = 0;
            while (i < ticks) : (i += 1) {
                clock_interface.sleep(tick_duration);
                final_time = clock_interface.milliTimestamp();
            }

            return final_time;
        }
    }.tick;

    // Test with MockClock for deterministic results
    var mock_clock = Clock.MockClock.init(0);
    var mock_interface = mock_clock.clock();

    const ticks = 5;
    const expected_time = ticks * 100; // 5 ticks * 100ms = 500ms
    const mock_result = tickingFunction(&mock_interface, ticks);

    try testing.expectEqual(expected_time, mock_result);

    // Can also use with SystemClock, but can't make deterministic assertions
    // Just verify it runs without errors
    var sys_clock = Clock.SystemClock.init();
    var sys_interface = sys_clock.clock();

    _ = tickingFunction(&sys_interface, 1);
}
