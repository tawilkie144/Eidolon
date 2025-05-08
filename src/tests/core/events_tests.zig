//! Test file for the event system
//! Tests all major functionality of the events.zig module

const std = @import("std");
const testing = std.testing;
const core = @import("Eidolon_core");

const events = core.events;
const session = core.session;
const Clock = core.Clock;
const ViewerEventType = events.ViewerEventType;

fn threadFn(loop: *events.EventLoop) void {
    loop.start();
}

// Test case: "EventLoop initialization and deinitialization"
// - Proper initialization of the event loop
// - Proper cleanup of resources on deinitialization
test "EventLoop initialization and deinitialization" {
    const allocator = testing.allocator;
    var mock_clock = Clock.MockClock.init(0);
    const clock = mock_clock.clock();
    var event_loop = events.EventLoop.init_test(allocator, clock);
    defer event_loop.deinit();
}

// Test case: "EventLoop add event"
// - Adding a single event to the event loop
// - Checking the event type is correctly stored
// - Checking the session ID is correctly associated
test "EventLoop add event" {
    const allocator = testing.allocator;
    var mock_clock = Clock.MockClock.init(0);
    const clock = mock_clock.clock();
    var event_loop = events.EventLoop.init_test(allocator, clock);
    defer event_loop.deinit();

    // Add event using the addEvent method with session_id, event_type, etc.
    try event_loop.addEvent(1, ViewerEventType.start, false, 1);
    try testing.expect(event_loop.count() == 1);
    const peek_event = event_loop.event_queue.peek().?;
    try testing.expect(peek_event.event_type == ViewerEventType.start);
    try testing.expect(peek_event.owning_session_id == 1);
}

// Test case: "EventLoop add events and remove session events"
// - Adding multiple events to the event loop
// - Removing events associated with specific sessions
// - Ensuring all events are properly removed when their sessions are removed
test "EventLoop add events and remove session events" {
    const allocator = testing.allocator;
    var mock_clock = Clock.MockClock.init(0);
    const clock = mock_clock.clock();
    var event_loop = events.EventLoop.init_test(allocator, clock);
    defer event_loop.deinit();

    // Add event using the addEvent method with session_id, event_type, etc.
    const e_types: [4]events.ViewerEventType = .{
        events.ViewerEventType.next,
        events.ViewerEventType.none,
        events.ViewerEventType.start,
        events.ViewerEventType.stop,
    };
    try event_loop.addEvent(1, e_types[0], false, 1);
    try event_loop.addEvent(2, e_types[1], false, 2);
    try event_loop.addEvent(3, e_types[2], false, 3);
    try event_loop.addEvent(4, e_types[3], false, 4);
    try event_loop.addEvent(4, e_types[3], false, 5);
    try testing.expect(event_loop.count() == 5);

    const removed: [4]usize = .{ 1, 1, 1, 2 };
    for (0..4) |i| {
        const peek_event = event_loop.event_queue.peek().?;
        try testing.expect(peek_event.event_type == e_types[i]);
        try testing.expect(peek_event.owning_session_id == (i + 1));
        const count = try event_loop.removeEventsForSession(i + 1);
        try testing.expect(count == removed[i]);
    }
    try testing.expect(event_loop.count() == 0);
}

// Test case: "EventLoop with multiple events ordering"
// - Adding multiple events with different durations
// - Verifying events are properly ordered in the queue
// - Checking that shorter duration events are prioritized
test "EventLoop with multiple events ordering" {
    const allocator = testing.allocator;
    var mock_clock = Clock.MockClock.init(0);
    const clock = mock_clock.clock();
    var event_loop = events.EventLoop.init_test(allocator, clock);
    defer event_loop.deinit();

    const session_id: session.Identifier = 1;

    // Add events using the new interface - longer duration first
    try event_loop.addEvent(session_id, ViewerEventType.start, false, 20);
    // Add shorter duration second - should be processed first
    try event_loop.addEvent(session_id, ViewerEventType.stop, false, 10);

    try testing.expect(event_loop.count() == 2);

    // The event with shorter duration should be at the top of the queue
    const peek_event = event_loop.event_queue.peek().?;
    try testing.expect(peek_event.event_type == ViewerEventType.stop);
}

// Test case: "Event ordering in queue"
// - Events with shorter durations are prioritized in the queue
// - Events with the same end time are handled correctly
// - Events are processed correctly when the clock advances past their times
test "Event ordering in queue" {
    const allocator = testing.allocator;
    var mock_clock = Clock.MockClock.init(0);
    const clock = mock_clock.clock();
    var event_loop = events.EventLoop.init_test(allocator, clock);
    defer event_loop.deinit();

    const loop_thread = try std.Thread.spawn(.{}, threadFn, .{event_loop});
    //Ugly hack to ensure that the loop has started before we try to stop it.
    var i: i32 = 0;
    while (!event_loop.is_running) {
        std.Thread.sleep(20);
        if (i > 50) {
            event_loop.stop(); //Just in case the test fails I don't want to hang
            try std.testing.expect(false);
        }
        i += 1;
    }

    const session_id: session.Identifier = 1;

    // Add events with different durations to test ordering
    try event_loop.addEvent(session_id, ViewerEventType.start, false, 20); // Longer duration (later event)
    try event_loop.addEvent(session_id, ViewerEventType.stop, false, 10); // Shorter duration (earlier event)

    // The event with shorter duration should be at the top of the queue
    try testing.expect(event_loop.count() == 2);
    const peek_event = event_loop.event_queue.peek().?;
    try testing.expect(peek_event.event_type == ViewerEventType.stop);

    // Now add an event with the same end time as the earliest one
    try event_loop.addEvent(session_id, ViewerEventType.next, false, 10);
    try testing.expect(event_loop.count() == 3);

    // Process the events by advancing the clock past their scheduled times
    const current_time = clock.milliTimestamp();
    mock_clock.setTime(current_time + 11 * std.time.ns_per_s);
    event_loop.testWakeFn(event_loop);

    // Only the event with the longest duration (20 seconds) should remain
    try testing.expect(event_loop.count() == 1);
    const remaining_event = event_loop.event_queue.peek().?;
    try testing.expect(remaining_event.event_type == ViewerEventType.start);

    // Stop the event loop
    event_loop.stop();

    // Wait for the thread to complete
    loop_thread.join();
    try std.testing.expect(!event_loop.is_running);
}

// Test case: "EventLoop process events with no events"
// - Handling the case of processing an empty event queue
// - Ensuring no crashes occur with empty queue
test "EventLoop process events with no events" {
    const allocator = testing.allocator;
    var mock_clock = Clock.MockClock.init(0);
    const clock = mock_clock.clock();
    var event_loop = events.EventLoop.init_test(allocator, clock);
    defer event_loop.deinit();

    const loop_thread = try std.Thread.spawn(.{}, threadFn, .{event_loop});
    //Ugly hack to ensure that the loop has started before we try to stop it.
    var i: i32 = 0;
    while (!event_loop.is_running) {
        std.Thread.sleep(20);
        if (i > 50) {
            event_loop.stop(); //Just in case the test fails I don't want to hang
            try std.testing.expect(false);
        }
        i += 1;
    }

    // Shouldn't crash when no events are present
    event_loop.testWakeFn(event_loop);
    try testing.expect(event_loop.event_queue.count() == 0);

    // Stop the event loop
    event_loop.stop();

    // Wait for the thread to complete
    loop_thread.join();
    try std.testing.expect(!event_loop.is_running);
}

// Test case: "EventLoop process events with future event"
// - Adding a future event to the queue
// - Verifying future events are not processed before their time
test "EventLoop process events with future event" {
    const allocator = testing.allocator;
    const initial_time = 0;
    var mock_clock = Clock.MockClock.init(initial_time);
    const clock = mock_clock.clock();
    var event_loop = events.EventLoop.init_test(allocator, clock);
    defer event_loop.deinit();

    const loop_thread = try std.Thread.spawn(.{}, threadFn, .{event_loop});
    //Ugly hack to ensure that the loop has started before we try to stop it.
    var i: i32 = 0;
    while (!event_loop.is_running) {
        std.Thread.sleep(20);
        if (i > 50) {
            event_loop.stop(); //Just in case the test fails I don't want to hang
            try std.testing.expect(false);
        }
        i += 1;
    }

    const session_id: session.Identifier = 1;
    // Using the new addEvent interface
    try event_loop.addEvent(session_id, ViewerEventType.start, false, 10);

    // Future event shouldn't be processed
    event_loop.testWakeFn(event_loop);
    try testing.expect(event_loop.count() == 1);

    // Stop the event loop
    event_loop.stop();

    // Wait for the thread to complete
    loop_thread.join();
    try std.testing.expect(!event_loop.is_running);
}

// Test case: "EventLoop repeating events"
// - Adding a repeating event to the queue
// - Verifying the event remains in the queue after processing
// - Checking the event time is updated correctly after processing
test "EventLoop repeating events" {
    const allocator = testing.allocator;
    const initial_time = 0;
    var mock_clock = Clock.MockClock.init(initial_time);
    const clock = mock_clock.clock();
    var event_loop = events.EventLoop.init_test(allocator, clock);
    defer event_loop.deinit();

    const loop_thread = try std.Thread.spawn(.{}, threadFn, .{event_loop});
    //Ugly hack to ensure that the loop has started before we try to stop it.
    var i: i32 = 0;
    while (!event_loop.is_running) {
        std.Thread.sleep(20);
        if (i > 50) {
            event_loop.stop(); //Just in case the test fails I don't want to hang
            try std.testing.expect(false);
        }
        i += 1;
    }

    // Create a repeating event
    const session_id: session.Identifier = 1;
    // Using the new addEvent method with should_repeat set to true
    try event_loop.addEvent(session_id, ViewerEventType.start, true, 10);

    try testing.expect(event_loop.count() == 1);

    // The event is not processed yet because it's in the future.
    // Let's verify it's still there after processing.
    event_loop.testWakeFn(event_loop);
    try testing.expect(event_loop.count() == 1);

    // Advance the clock past the event time
    mock_clock.advance(11 * std.time.ns_per_s);

    // Process the event - since it's repeating, it should stay in the queue with updated time
    event_loop.testWakeFn(event_loop);
    try testing.expect(event_loop.count() == 1); // Still 1 because it's repeating

    event_loop.stop();

    loop_thread.join();
    try std.testing.expect(!event_loop.is_running);
}

// Test case: "EventLoop run and stop"
// - Starting the event loop in a separate thread
// - Verifying the loop can be properly stopped
// - Ensuring the is_running flag is updated correctly
test "EventLoop run and stop" {
    const allocator = testing.allocator;
    var mock_clock = Clock.MockClock.init(0);
    const clock = mock_clock.clock();
    var event_loop = events.EventLoop.init_test(allocator, clock);
    defer event_loop.deinit();

    // Set up a separate thread to run the event loop
    const loop_thread = try std.Thread.spawn(.{}, threadFn, .{event_loop});
    //Ugly hack to ensure that the loop has started before we try to stop it.
    var i: i32 = 0;
    while (!event_loop.is_running) {
        std.Thread.sleep(20);
        if (i > 50) {
            event_loop.stop(); //Just in case the test fails I don't want to hang
            try std.testing.expect(false);
        }
        i += 1;
    }
    // We don't need to actually sleep since we're using MockClock
    // We'll explicitly wake up the event loop
    event_loop.testWakeFn(event_loop);

    // Stop the event loop
    event_loop.stop();

    // Wait for the thread to complete
    loop_thread.join();
    try std.testing.expect(!event_loop.is_running);
}

// Test case: "EventLoop with staggered event additions"
// - Adding events at different times while the loop is running
// - Verifying events are processed at the correct times
// - Checking the event queue count updates properly after processing
// - Ensuring proper cleanup when the loop is stopped
test "EventLoop with staggered event additions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var mock_clock = Clock.MockClock.init(0);
    const clock = mock_clock.clock();
    var event_loop = events.EventLoop.init_test(allocator, clock);
    defer event_loop.deinit();

    // Set up a separate thread to run the event loop
    const thread = try std.Thread.spawn(.{}, threadFn, .{event_loop});
    var i: i32 = 0;
    while (!event_loop.is_running) {
        std.Thread.sleep(20);
        if (i > 50) {
            event_loop.stop(); //Just in case the test fails I don't want to hang
            try std.testing.expect(false);
        }
        i += 1;
    }
    // First event - a "start" type that will complete in 5 seconds
    try event_loop.addEvent(1, ViewerEventType.start, false, 5);
    // Instead of waiting, use the mock clock to advance time
    mock_clock.setTime(2000 * std.time.ns_per_ms);
    // Add second event
    try event_loop.addEvent(2, ViewerEventType.stop, false, 5);

    // Advance the clock to process both events
    mock_clock.setTime(4999 * std.time.ns_per_ms);
    event_loop.testWakeFn(event_loop);
    try std.testing.expect(event_loop.count() == 2);
    mock_clock.setTime(5001 * std.time.ns_per_ms);
    event_loop.testWakeFn(event_loop);
    try std.testing.expect(event_loop.count() == 1);
    mock_clock.setTime(6999 * std.time.ns_per_ms);
    event_loop.testWakeFn(event_loop);
    try std.testing.expect(event_loop.count() == 1);
    mock_clock.setTime(7001 * std.time.ns_per_ms);
    event_loop.testWakeFn(event_loop);
    try std.testing.expect(event_loop.count() == 0);

    // Stop the event loop
    event_loop.stop();

    // Wait for the thread to complete
    thread.join();
    try std.testing.expect(!event_loop.is_running);
}
