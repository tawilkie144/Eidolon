const std = @import("std");

const scheduling = @import("scheduler.zig");
const logging = @import("logger.zig");

const Scheduler = scheduling.Scheduler;
const Logger = logging.Logger;

pub const Identifier = u128;

pub const Session = struct {
    pub const SpecifierType = enum {
        duration,
        count,
        image_duration,
    };
    pub const Specifier = union(SpecifierType) {
        duration: u16,
        count: u16,
        image_duration: u16,
    };

    id: Identifier, // TODO: This will be changed to some sort of unique identifier
    user: u128, // TODO: The user that this session belongs to. Not sure what type this will be or where it is sourced from
    loop: bool, // IF true, the duration will be 0
    shuffle: bool,
    duration: u16, // The duration of the session in seconds. If 0 then there will be no timed stopping point and loop will be true
    image_duration: u16, // The duration each image is displayed before moving onto the next
    image_count: u16, // The number of images to display. If not provided, the display
    // the entire gallery and will be provided by the image loader
    tags: std.ArrayList([]const u8), // TODO: I'm not sure the best way to handle tags at the moment.
    progress: u8, // The percentage through the gallery the session currently is at
    image_progress: u8, // TODO: The percentage throug the current image time the session currently is
    // -> i think this will end up being removed and delegated to the client to calculate

    // pub fn start(self: *Session) !void {
    //     return;
    // }

    // pub fn stop(self: *Session) !void {
    //     return;
    // }

    // pub fn pause(self: *Session) !void {
    //     return;
    // }

    // pub fn play(self: *Session) !void {
    //     return;
    // }

    pub fn addTags(self: *Session, tags_to_add: std.ArrayList([]const u8)) !void {
        try self.tags.appendSlice(tags_to_add.items);
        return;
    }
};

/// Allocates memory for a SessionCoordinator via create. It is the callers responsibility to destroy
/// via DestroySessionCoordinator.
pub fn CreateSessionCoordinator(allocator: std.mem.Allocator) !*SessionCoordinator {
    const r_coordinator = try allocator.create(SessionCoordinator);
    r_coordinator.scheduler = undefined; //TODO: When the scheduler is created
    r_coordinator.logger = undefined; //TODO: When the logger is created
    r_coordinator.sessions = std.AutoHashMap(Identifier, Session).init(allocator);
    return r_coordinator;
}

pub fn DestroySessionCoordinator(coordinator: *SessionCoordinator, allocator: std.mem.Allocator) void {
    coordinator.sessions.deinit();
    //TODO: do something with the logger
    //TODO: do something with the scheduler
    allocator.destroy(coordinator);
}

pub const SessionCoordinator = struct {
    pub const DurationClip = enum {
        session,
        image,
        none,
    };

    sessions: std.AutoHashMap(Identifier, Session),
    scheduler: Scheduler, //TODO
    logger: Logger, //TODO

    const session_defaults = .{ .shuffle = true, .loop = false, .image_count = 60, .image_duration = 60, .duration = 3600 };

    /// Creates and stores a session.
    /// Memory is allocated for the sessions tags which must be freed when removed by destroySession
    pub fn createGallerySession(self: *SessionCoordinator, user: u128, shuffle: bool, image_duration: u16, tags: std.ArrayList([]const u8)) !Identifier {
        const id = 0; // TODO: Create new unique id here
        const session_tags = try tags.clone();
        const session: Session = .{ .id = id, .user = user, .loop = true, .shuffle = shuffle, .duration = 0, .image_duration = image_duration, .image_count = undefined, .tags = session_tags, .progress = 0, .image_progress = 0 };
        try self.sessions.put(id, session);
        return id;
    }

    /// Creates and stores a session.
    /// Memory is allocated for the sessions tags which must be freed when removed by destroySession
    pub fn createSession(self: *SessionCoordinator, user: u128, loop: bool, shuffle: bool, option_one: Session.Specifier, option_two: Session.Specifier, clip: SessionCoordinator.DurationClip, tags: std.ArrayList([]const u8)) !Identifier {
        const id = 1; // TODO: Create new unique id here
        var session_duration: u16 = undefined;
        var image_duration: u16 = undefined;
        var image_count: u16 = undefined;
        if ((option_one == .count and option_two == .count) or (option_one == .duration and option_two == .duration) or (option_one == .image_duration and option_two == .image_duration)) {
            Logger.logSystem(.warn, .session, "Invalid session parameters for session {d}, setting to defaults", .{id});
            session_duration = SessionCoordinator.session_defaults.duration;
            image_duration = SessionCoordinator.session_defaults.image_duration;
            image_count = SessionCoordinator.session_defaults.image_count;
        } else {
            switch (option_one) {
                .duration => |value| session_duration = value,
                .count => |value| image_count = value,
                .image_duration => |value| image_duration = value,
            }
            switch (option_two) {
                .duration => |value| session_duration = value,
                .count => |value| image_count = value,
                .image_duration => |value| image_duration = value,
            }
        }

        if (image_duration * image_count != session_duration) {
            // TODO: For now, all of these have the same behavior until I know how the scheduler works.
            switch (clip) {
                .session => {
                    session_duration = image_duration * image_count;
                },
                .image => {
                    session_duration = image_duration * image_count;
                },
                .none => {
                    session_duration = image_duration * image_count;
                },
            }
        }
        const session_tags = try tags.clone();
        try self.sessions.put(id, .{ .id = id, .user = user, .loop = loop, .shuffle = shuffle, .duration = session_duration, .image_duration = image_duration, .image_count = image_count, .tags = session_tags, .progress = 0, .image_progress = 0 });
        return id;
    }

    pub fn destroySession(self: *SessionCoordinator, id: u128) void {
        const session = self.sessions.get(id) orelse return;
        session.tags.deinit();
        _ = self.sessions.remove(id);
    }
};
