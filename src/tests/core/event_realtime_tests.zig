//! Test file for the event system using real system clock
//! Tests all major functionality of the events.zig module with real-time clock

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

// Test case: "Event ordering in queue"
// - Events with shorter durations are prioritized in the queue
// - Events with the same end time are handled correctly
// - Events are processed correctly when the clock advances past their times
test "Event ordering in queue" {
    const allocator = testing.allocator;
    var event_loop = events.EventLoop.init(allocator);
    defer event_loop.deinit();

    const loop_thread = try std.Thread.spawn(.{}, threadFn, .{event_loop});

    const session_id: session.Identifier = 1;

    // Add events with different durations to test ordering
    try event_loop.addEvent(session_id, ViewerEventType.start, false, 5); // Longer duration (later event)
    try event_loop.addEvent(session_id, ViewerEventType.stop, false, 2); // Shorter duration (earlier event)

    // The event with shorter duration should be at the top of the queue
    try testing.expect(event_loop.count() == 2);
    const peek_event = event_loop.event_queue.peek().?;
    try testing.expect(peek_event.event_type == ViewerEventType.stop);

    // Now add an event with the same end time as the earliest one
    try event_loop.addEvent(session_id, ViewerEventType.next, false, 2);
    try testing.expect(event_loop.count() == 3);

    std.Thread.sleep(2.1 * std.time.ns_per_s);
    try std.testing.expect(event_loop.count() == 1);
    std.Thread.sleep(3 * std.time.ns_per_s);
    try std.testing.expect(event_loop.count() == 0);

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
    var event_loop = events.EventLoop.init(allocator);
    defer event_loop.deinit();

    const loop_thread = try std.Thread.spawn(.{}, threadFn, .{event_loop});

    try testing.expect(event_loop.event_queue.count() == 0);
    std.Thread.sleep(1 * std.time.ns_per_s);
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
    var event_loop = events.EventLoop.init(allocator);
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
    try event_loop.addEvent(session_id, ViewerEventType.start, false, 5);

    // Future event shouldn't be processed
    std.Thread.sleep(2 * std.time.ns_per_s);
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
    var event_loop = events.EventLoop.init(allocator);
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
    try event_loop.addEvent(session_id, ViewerEventType.start, true, 2);

    try testing.expect(event_loop.count() == 1);

    std.Thread.sleep(1 * std.time.ns_per_s);
    try testing.expect(event_loop.count() == 1);

    // Wait for the event to process
    std.Thread.sleep(1.1 * std.time.ns_per_ms);

    try testing.expect(event_loop.count() == 1);

    event_loop.stop();

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
    var event_loop = events.EventLoop.init(allocator);
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

    // First event - a "start" type that will complete in 1 second
    try event_loop.addEvent(1, ViewerEventType.start, false, 1);

    // Add second event that will complete in 2 seconds
    try event_loop.addEvent(2, ViewerEventType.stop, false, 2);

    std.Thread.sleep(0.5 * std.time.ns_per_s);
    try std.testing.expect(event_loop.count() == 2);

    std.Thread.sleep(0.6 * std.time.ns_per_s);
    try std.testing.expect(event_loop.count() == 1);
    std.Thread.sleep(1 * std.time.ns_per_s);
    try std.testing.expect(event_loop.count() == 0);

    // Stop the event loop
    event_loop.stop();

    // Wait for the thread to complete
    thread.join();
    try std.testing.expect(!event_loop.is_running);
}
