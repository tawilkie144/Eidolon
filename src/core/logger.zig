//! Logger module for Eidolon providing standardized logging capabilities.
//! Integrates with Zig's std.log while providing convenient event-specific logging.

const std = @import("std");

/// Log scopes for different components of the application
pub const LogScope = enum {
    event_system,
    session,
    image_loader,
    scheduler,
    system,
};

/// Logger utility for consistent logging across the application
pub const Logger = struct {
    /// Log an event processing message with the specified log level
    pub fn logEvent(
        comptime level: std.log.Level,
        event_type: anytype,
        session_id: anytype,
        comptime format: []const u8,
        args: anytype,
    ) void {
        const scoped_logger = std.log.scoped(.event_system);
        const timestamp = std.time.milliTimestamp();

        switch (level) {
            .err => scoped_logger.err("[{d}] Event {s} for session {}: " ++ format, .{ timestamp, @tagName(event_type), session_id } ++ args),
            .warn => scoped_logger.warn("[{d}] Event {s} for session {}: " ++ format, .{ timestamp, @tagName(event_type), session_id } ++ args),
            .info => scoped_logger.info("[{d}] Event {s} for session {}: " ++ format, .{ timestamp, @tagName(event_type), session_id } ++ args),
            .debug => scoped_logger.debug("[{d}] Event {s} for session {}: " ++ format, .{ timestamp, @tagName(event_type), session_id } ++ args),
        }
    }

    fn getLogScope(comptime scope: LogScope) type {
        switch (scope) {
            .event_system => return std.log.scoped(.event_system),
            .session => return std.log.scoped(.session),
            .image_loader => return std.log.scoped(.image_loader),
            .scheduler => return std.log.scoped(.scheduler),
            .system => return std.log.scoped(.system),
        }
    }

    /// Log system messages with the specified log level
    pub fn logSystem(
        comptime level: std.log.Level,
        comptime scope: LogScope,
        comptime format: []const u8,
        args: anytype,
    ) void {
        const scoped_logger = getLogScope(scope);

        switch (level) {
            .err => scoped_logger.err(format, args),
            .warn => scoped_logger.warn(format, args),
            .info => scoped_logger.info(format, args),
            .debug => scoped_logger.debug(format, args),
        }
    }

    /// Convenience function for logging event processing at info level
    pub fn eventProcessed(
        event_type: anytype,
        session_id: anytype,
        comptime format: []const u8,
        args: anytype,
    ) void {
        logEvent(.info, event_type, session_id, format, args);
    }

    /// Convenience function for logging event creation at debug level
    pub fn eventCreated(
        event_type: anytype,
        session_id: anytype,
        comptime format: []const u8,
        args: anytype,
    ) void {
        logEvent(.debug, event_type, session_id, format, args);
    }

    /// Convenience function for logging event errors at error level
    pub fn eventError(
        event_type: anytype,
        session_id: anytype,
        comptime format: []const u8,
        args: anytype,
    ) void {
        logEvent(.err, event_type, session_id, format, args);
    }
};
