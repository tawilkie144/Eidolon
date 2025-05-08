//! Event management system for the Eidolon viewer.
//! Provides a priority queue of events that are processed in order of time_to_remove.

const std = @import("std");
const session = @import("session.zig");

const EidolonLogging = @import("logger.zig");
const EidolonClock = @import("clock.zig");

/// Errors that can occur when working with viewer events
pub const ViewerEventErrors = error{
    NoEventQueued,
    EventAllocationFailed,
};

/// Types of events that can be triggered in the viewer
pub const ViewerEventType = enum { start, stop, next, none };

/// Comparison function for ViewerEvents to determine their priority order
pub fn compareViewerEvents(_: void, a: EventLoop.ViewerEvent, b: EventLoop.ViewerEvent) std.math.Order {
    if (a.time_to_remove == b.time_to_remove) {
        return std.math.Order.eq;
    } else if (a.time_to_remove < b.time_to_remove) {
        return std.math.Order.lt;
    } else {
        return std.math.Order.gt;
    }
}

/// Event processing loop that manages timed events
pub const EventLoop = struct {
    allocator: std.mem.Allocator,
    event_queue: std.PriorityQueue(ViewerEvent, void, compareViewerEvents),
    is_running: bool,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    clock: EidolonClock.Clock,
    testWakeFn: *const fn (*EventLoop) void, // set for tests to avoid sleeping

    /// Represents a timed event in the viewer
    const ViewerEvent = struct {
        time_added: i64,
        time_to_remove: i64,
        event_type: ViewerEventType,
        owning_session_id: session.Identifier,
        should_repeat: bool,

        /// Creates a new ViewerEvent.
        ///
        /// Parameters:
        ///   - session_id: The identifier of the session that owns this event
        ///   - event_type: The type of event to create
        ///   - should_repeat: Whether this event should repeat after being processed
        ///   - duration_of_event_seconds: How many seconds until this event should trigger
        fn create(
            session_id: session.Identifier,
            event_type: ViewerEventType,
            should_repeat: bool,
            duration_of_event_seconds: u32,
            clock: EidolonClock.Clock,
        ) ViewerEvent {
            const now = clock.milliTimestamp();
            const event_time = now + duration_of_event_seconds * std.time.ms_per_s;
            return .{
                .time_added = now,
                .time_to_remove = event_time,
                .event_type = event_type,
                .owning_session_id = session_id,
                .should_repeat = should_repeat,
            };
        }
    };

    /// Initialize a new EventLoop with the given allocator
    /// The caller is responsible for calling deinit()
    pub fn init(allocator: std.mem.Allocator) *EventLoop {
        const self = allocator.create(EventLoop) catch {
            EidolonLogging.Logger.logSystem(.err, .event_system, "Failed to allocate memory for EventLoop", .{});
            @panic("Out of memory");
        };
        var system_clock = EidolonClock.SystemClock.init();
        self.* = .{
            .event_queue = std.PriorityQueue(ViewerEvent, void, compareViewerEvents).init(allocator, {}),
            .allocator = allocator,
            .is_running = false,
            .mutex = std.Thread.Mutex{},
            .cond = std.Thread.Condition{},
            .clock = system_clock.clock(),
            .testWakeFn = noopWakeEventLoop,
        };
        return self;
    }

    /// Used for testing, can accept a controllable clock for testing purposes
    /// Do not use for production code
    pub fn init_test(allocator: std.mem.Allocator, clock: EidolonClock.Clock) *EventLoop {
        const self = allocator.create(EventLoop) catch {
            EidolonLogging.Logger.logSystem(.err, .event_system, "Failed to allocate memory for EventLoop", .{});
            @panic("Out of memory");
        };

        self.* = .{
            .event_queue = std.PriorityQueue(ViewerEvent, void, compareViewerEvents).init(allocator, {}),
            .allocator = allocator,
            .is_running = false,
            .mutex = std.Thread.Mutex{},
            .cond = std.Thread.Condition{},
            .clock = clock,
            .testWakeFn = wakeTestEventLoop,
        };
        return self;
    }

    /// Free resources associated with the EventLoop
    pub fn deinit(self: *EventLoop) void {
        self.stop();
        self.event_queue.deinit();
        self.allocator.destroy(self);
    }

    /// Start the event loop processing
    pub fn start(self: *EventLoop) void {
        self.mutex.lock();
        self.is_running = true;
        self.mutex.unlock();

        while (self.is_running) {
            self.processEvents();
            self.sleepUntilNextEvent();
        }
    }

    /// Stops the event loop if it's running
    pub fn stop(self: *EventLoop) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_running) {
            self.is_running = false;
            self.cond.signal();
        }
    }

    pub fn count(self: *EventLoop) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.event_queue.count();
    }

    pub fn addEvent(self: *EventLoop, session_id: session.Identifier, event_type: ViewerEventType, should_repeat: bool, duration_of_event_seconds: u32) ViewerEventErrors!void {
        const event = ViewerEvent.create(session_id, event_type, should_repeat, duration_of_event_seconds, self.clock);
        try self.addEvent_existing(event);
    }

    /// Add an event to the queue
    fn addEvent_existing(self: *EventLoop, event: ViewerEvent) ViewerEventErrors!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Log event creation
        const logger = EidolonLogging.Logger;
        logger.eventCreated(event.event_type, event.owning_session_id, "inserted event at {}: scheduled for {} ms from now", .{ self.clock.milliTimestamp(), event.time_to_remove - event.time_added });

        self.event_queue.add(event) catch {
            logger.eventError(event.event_type, event.owning_session_id, "failed to add event to queue", .{});
            return ViewerEventErrors.EventAllocationFailed;
        };
        self.cond.broadcast();
    }

    pub fn removeEventsForSession(self: *EventLoop, session_id: session.Identifier) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list_to_remove = std.ArrayList(usize).init(self.allocator);
        defer list_to_remove.deinit();

        for (0..self.event_queue.items.len) |i| {
            const event = self.event_queue.items[i];
            if (event.owning_session_id == session_id) {
                try list_to_remove.append(i);
            }
        }
        std.sort.heap(usize, list_to_remove.items, {}, comptime std.sort.desc(usize));
        for (list_to_remove.items) |index| {
            _ = self.event_queue.removeIndex(index);
        }

        return list_to_remove.items.len;
    }

    /// Calculate time until the next event needs to be processed
    /// Returns: Time in milliseconds until the next event or an error if no events are queued
    fn timeUntilNextEvent(self: *EventLoop) ViewerEventErrors!u64 {
        if (self.event_queue.peek()) |next_event| {
            const now = self.clock.milliTimestamp();
            return @as(u64, @intCast(@max(0, next_event.time_to_remove - now)));
        }
        return ViewerEventErrors.NoEventQueued;
    }

    /// Sleep until the next event is ready to be processed or until a new event is added
    fn sleepUntilNextEvent(self: *EventLoop) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.is_running) {
            const time_result = self.timeUntilNextEvent();
            if (time_result) |time| {
                if (time <= 0) {
                    return;
                }
                self.cond.timedWait(&self.mutex, time * std.time.ns_per_ms) catch {};
            } else |err| switch (err) {
                ViewerEventErrors.NoEventQueued => {
                    self.cond.wait(&self.mutex);
                },
                else => {
                    EidolonLogging.Logger.logSystem(.err, .event_system, "Unexpected error: {}", .{err});
                },
            }
        }
    }

    /// Process any events that are ready to be executed
    fn processEvents(self: *EventLoop) void {
        const logger = EidolonLogging.Logger;
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.event_queue.peek()) |next_event| {
            const now = self.clock.milliTimestamp();
            if (now >= next_event.time_to_remove) {
                const removed_event = self.event_queue.remove();

                // Handle the event and log with our new logger
                switch (removed_event.event_type) {
                    ViewerEventType.start => {
                        logger.eventProcessed(removed_event.event_type, removed_event.owning_session_id, "Event processed at {}: processed after {}ms", .{ self.clock.milliTimestamp(), now - removed_event.time_added });
                    },
                    ViewerEventType.stop => {
                        logger.eventProcessed(removed_event.event_type, removed_event.owning_session_id, "Event processed at {}: processed after {}ms", .{ self.clock.milliTimestamp(), now - removed_event.time_added });
                    },
                    ViewerEventType.next => {
                        logger.eventProcessed(removed_event.event_type, removed_event.owning_session_id, "Event processed at {}: processed after {}ms", .{ self.clock.milliTimestamp(), now - removed_event.time_added });
                    },
                    ViewerEventType.none => {
                        // No action needed
                        logger.logSystem(.warn, .event_system, "Received 'none' event type, ignoring", .{});
                    },
                }

                // If the event should repeat, add it back to the queue
                if (removed_event.should_repeat) {
                    var repeated_event = removed_event;
                    const repeat_interval = repeated_event.time_to_remove - repeated_event.time_added;
                    repeated_event.time_added = now;
                    repeated_event.time_to_remove = now + repeat_interval;

                    self.event_queue.add(repeated_event) catch {
                        logger.eventError(removed_event.event_type, removed_event.owning_session_id, "failed to re-add repeating event", .{});
                    };
                }
            } else {
                // If the next event isn't ready yet, stop processing
                break;
            }
        }
    }
};

fn noopWakeEventLoop(_: *EventLoop) void {
    EidolonLogging.Logger.logSystem(.err, .event_system, "Using wakeTestEventLoop function in real-time code!", .{});
    return;
}

fn wakeTestEventLoop(self: *EventLoop) void {
    self.cond.signal();
    std.Thread.sleep(100);
}
