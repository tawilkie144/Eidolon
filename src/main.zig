const std = @import("std");
const core = @import("Eidolon_core");

const events = core.events;
const session = core.session;
const EidolonLogging = core.logger;
const LogScope = EidolonLogging.LogScope;
const EidolonClock = core.Clock;

fn threadFn(loop: *events.EventLoop) void {
    loop.start();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var event_loop = events.EventLoop.init(allocator);
    defer event_loop.deinit();

    const loop_thread = try std.Thread.spawn(.{}, threadFn, .{event_loop});

    const session_id: session.Identifier = 1;

    // Add events with different durations to test ordering
    try event_loop.addEvent(session_id, events.ViewerEventType.start, false, 10); // Longer duration (later event)
    try event_loop.addEvent(session_id, events.ViewerEventType.stop, false, 5); // Shorter duration (earlier event)

    // The event with shorter duration should be at the top of the queue
    std.debug.print("Event Count: {} (expecting 2)", .{event_loop.count()}); //try testing.expect(event_loop.count() == 2);
    const peek_event = event_loop.event_queue.peek().?;
    std.debug.print("Top event Type: {} (expecting stop)", .{peek_event.event_type}); //try testing.expect(peek_event.event_type == ViewerEventType.stop);

    // Now add an event with the same end time as the earliest one
    try event_loop.addEvent(session_id, events.ViewerEventType.next, false, 5);
    std.debug.print("", .{}); //try testing.expect(event_loop.count() == 3);

    std.Thread.sleep(5.2 * std.time.ns_per_s);
    std.debug.print("", .{}); //try std.testing.expect(event_loop.count() == 1);
    std.Thread.sleep(5 * std.time.ns_per_s);
    std.debug.print("", .{}); //try std.testing.expect(event_loop.count() == 0);

    // Stop the event loop
    event_loop.stop();

    // Wait for the thread to complete
    loop_thread.join();
    try std.testing.expect(!event_loop.is_running);
}
