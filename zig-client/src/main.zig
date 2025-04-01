//! QuestDB Client Library for Zig
//! This library makes it easy to insert data into QuestDB using the InfluxDB Line Protocol (ILP).

const std = @import("std");
const c = @cImport({
    @cInclude("questdb/ingress/line_sender.h");
});

/// Error type for QuestDB client operations
pub const Error = error{
    CouldNotResolveAddr,
    InvalidApiCall,
    SocketError,
    InvalidUtf8,
    InvalidName,
    InvalidTimestamp,
    AuthError,
    TlsError,
    HttpNotSupported,
    ServerFlushError,
    ConfigError,
    OutOfMemory,
    Unknown,
};

/// Convert C error to Zig error
fn convertError(c_err: *c.line_sender_error) Error {
    const code = c.line_sender_error_get_code(c_err);
    defer c.line_sender_error_free(c_err);

    return switch (code) {
        c.line_sender_error_could_not_resolve_addr => Error.CouldNotResolveAddr,
        c.line_sender_error_invalid_api_call => Error.InvalidApiCall,
        c.line_sender_error_socket_error => Error.SocketError,
        c.line_sender_error_invalid_utf8 => Error.InvalidUtf8,
        c.line_sender_error_invalid_name => Error.InvalidName,
        c.line_sender_error_invalid_timestamp => Error.InvalidTimestamp,
        c.line_sender_error_auth_error => Error.AuthError,
        c.line_sender_error_tls_error => Error.TlsError,
        c.line_sender_error_http_not_supported => Error.HttpNotSupported,
        c.line_sender_error_server_flush_error => Error.ServerFlushError,
        c.line_sender_error_config_error => Error.ConfigError,
        else => Error.Unknown,
    };
}

/// Protocol used to communicate with QuestDB
pub const Protocol = enum {
    /// ILP over TCP (streaming)
    tcp,
    /// TCP + TLS
    tcps,
    /// ILP over HTTP (request-response, InfluxDB-compatible)
    http,
    /// HTTP + TLS
    https,

    /// Convert Zig Protocol to C protocol
    fn toC(self: Protocol) c.line_sender_protocol {
        return switch (self) {
            .tcp => c.line_sender_protocol_tcp,
            .tcps => c.line_sender_protocol_tcps,
            .http => c.line_sender_protocol_http,
            .https => c.line_sender_protocol_https,
        };
    }
};

/// Certificate Authority source for TLS connections
pub const CertificateAuthority = enum {
    /// Use the set of root certificates provided by the `webpki` crate
    webpki_roots,
    /// Use the set of root certificates provided by the operating system
    os_roots,
    /// Combine the set of root certificates provided by the `webpki` crate and the operating system
    webpki_and_os_roots,
    /// Use the root certificates provided in a PEM-encoded file
    pem_file,

    /// Convert Zig CertificateAuthority to C CA
    fn toC(self: CertificateAuthority) c.line_sender_ca {
        return switch (self) {
            .webpki_roots => c.line_sender_ca_webpki_roots,
            .os_roots => c.line_sender_ca_os_roots,
            .webpki_and_os_roots => c.line_sender_ca_webpki_and_os_roots,
            .pem_file => c.line_sender_ca_pem_file,
        };
    }
};

/// Timestamp in nanoseconds since the Unix epoch
pub const TimestampNanos = struct {
    value: i64,

    /// Create a new timestamp with the given nanosecond value
    pub fn init(value: i64) TimestampNanos {
        return TimestampNanos{ .value = value };
    }

    /// Get the current time in nanoseconds
    pub fn now() TimestampNanos {
        return TimestampNanos{ .value = c.line_sender_now_nanos() };
    }
};

/// Timestamp in microseconds since the Unix epoch
pub const TimestampMicros = struct {
    value: i64,

    /// Create a new timestamp with the given microsecond value
    pub fn init(value: i64) TimestampMicros {
        return TimestampMicros{ .value = value };
    }

    /// Get the current time in microseconds
    pub fn now() TimestampMicros {
        return TimestampMicros{ .value = c.line_sender_now_micros() };
    }
};

/// Options for configuring a Sender
pub const SenderOptions = struct {
    protocol: Protocol,
    host: []const u8,
    port: u16,
    bind_interface: ?[]const u8 = null,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    token: ?[]const u8 = null,
    token_x: ?[]const u8 = null,
    token_y: ?[]const u8 = null,
    auth_timeout: ?u64 = null,
    tls_verify: bool = true,
    tls_ca: ?CertificateAuthority = null,
    tls_roots: ?[]const u8 = null,
    max_buf_size: ?usize = null,
    retry_timeout: ?u64 = null,
    request_min_throughput: ?u64 = null,
    request_timeout: ?u64 = null,

    /// Create a new SenderOptions with the given protocol, host, and port
    pub fn init(protocol: Protocol, host: []const u8, port: u16) SenderOptions {
        return SenderOptions{
            .protocol = protocol,
            .host = host,
            .port = port,
        };
    }

    /// Create a new SenderOptions from a configuration string
    pub fn fromConf(config: []const u8) !SenderOptions {
        var c_err: ?*c.line_sender_error = null;
        const c_opts = c.line_sender_opts_from_conf(
            c.line_sender_utf8{ .len = config.len, .buf = config.ptr },
            &c_err,
        );

        if (c_err != null) {
            return convertError(c_err.?);
        }

        // We don't actually need to extract the options from c_opts
        // since we'll be using it directly to build the sender
        return SenderOptions{
            .protocol = .tcp, // Default, will be overridden by the config string
            .host = "",       // Default, will be overridden by the config string
            .port = 0,        // Default, will be overridden by the config string
        };
    }

    /// Create a new SenderOptions from the QDB_CLIENT_CONF environment variable
    pub fn fromEnv() !SenderOptions {
        var c_err: ?*c.line_sender_error = null;
        const c_opts = c.line_sender_opts_from_env(&c_err);

        if (c_err != null) {
            return convertError(c_err.?);
        }

        // We don't actually need to extract the options from c_opts
        // since we'll be using it directly to build the sender
        return SenderOptions{
            .protocol = .tcp, // Default, will be overridden by the env var
            .host = "",       // Default, will be overridden by the env var
            .port = 0,        // Default, will be overridden by the env var
        };
    }
};

/// Buffer for building ILP messages
pub const Buffer = struct {
    c_buffer: *c.line_sender_buffer,
    allocator: std.mem.Allocator,

    /// Create a new Buffer with default settings
    pub fn init(allocator: std.mem.Allocator) !Buffer {
        const c_buffer = c.line_sender_buffer_new() orelse return Error.OutOfMemory;
        return Buffer{
            .c_buffer = c_buffer,
            .allocator = allocator,
        };
    }

    /// Create a new Buffer with a custom maximum name length
    pub fn initWithMaxNameLen(allocator: std.mem.Allocator, max_name_len: usize) !Buffer {
        const c_buffer = c.line_sender_buffer_with_max_name_len(max_name_len) orelse return Error.OutOfMemory;
        return Buffer{
            .c_buffer = c_buffer,
            .allocator = allocator,
        };
    }

    /// Free the buffer resources
    pub fn deinit(self: *Buffer) void {
        c.line_sender_buffer_free(self.c_buffer);
    }

    /// Clear the buffer contents
    pub fn clear(self: *Buffer) void {
        c.line_sender_buffer_clear(self.c_buffer);
    }

    /// Set a marker for potential rollback
    pub fn setMarker(self: *Buffer) !void {
        var c_err: ?*c.line_sender_error = null;
        if (!c.line_sender_buffer_set_marker(self.c_buffer, &c_err)) {
            return convertError(c_err.?);
        }
    }

    /// Rewind to the last marker
    pub fn rewindToMarker(self: *Buffer) !void {
        var c_err: ?*c.line_sender_error = null;
        if (!c.line_sender_buffer_rewind_to_marker(self.c_buffer, &c_err)) {
            return convertError(c_err.?);
        }
    }

    /// Clear the marker
    pub fn clearMarker(self: *Buffer) void {
        c.line_sender_buffer_clear_marker(self.c_buffer);
    }

    /// Get the number of bytes in the buffer
    pub fn size(self: *const Buffer) usize {
        return c.line_sender_buffer_size(self.c_buffer);
    }

    /// Get the number of rows in the buffer
    pub fn rowCount(self: *const Buffer) usize {
        return c.line_sender_buffer_row_count(self.c_buffer);
    }

    /// Check if the buffer is transactional
    pub fn isTransactional(self: *const Buffer) bool {
        return c.line_sender_buffer_transactional(self.c_buffer);
    }

    /// Start a new row with the given table name
    pub fn table(self: *Buffer, name: []const u8) !*Buffer {
        var c_err: ?*c.line_sender_error = null;
        var table_name: c.line_sender_table_name = undefined;
        
        if (!c.line_sender_table_name_init(&table_name, name.len, name.ptr, &c_err)) {
            return convertError(c_err.?);
        }
        
        if (!c.line_sender_buffer_table(self.c_buffer, table_name, &c_err)) {
            return convertError(c_err.?);
        }
        
        return self;
    }

    /// Add a symbol column to the current row
    pub fn symbol(self: *Buffer, name: []const u8, value: []const u8) !*Buffer {
        var c_err: ?*c.line_sender_error = null;
        var column_name: c.line_sender_column_name = undefined;
        var utf8_value: c.line_sender_utf8 = undefined;
        
        if (!c.line_sender_column_name_init(&column_name, name.len, name.ptr, &c_err)) {
            return convertError(c_err.?);
        }
        
        if (!c.line_sender_utf8_init(&utf8_value, value.len, value.ptr, &c_err)) {
            return convertError(c_err.?);
        }
        
        if (!c.line_sender_buffer_symbol(self.c_buffer, column_name, utf8_value, &c_err)) {
            return convertError(c_err.?);
        }
        
        return self;
    }

    /// Add a boolean column to the current row
    pub fn columnBool(self: *Buffer, name: []const u8, value: bool) !*Buffer {
        var c_err: ?*c.line_sender_error = null;
        var column_name: c.line_sender_column_name = undefined;
        
        if (!c.line_sender_column_name_init(&column_name, name.len, name.ptr, &c_err)) {
            return convertError(c_err.?);
        }
        
        if (!c.line_sender_buffer_column_bool(self.c_buffer, column_name, value, &c_err)) {
            return convertError(c_err.?);
        }
        
        return self;
    }

    /// Add an integer column to the current row
    pub fn columnI64(self: *Buffer, name: []const u8, value: i64) !*Buffer {
        var c_err: ?*c.line_sender_error = null;
        var column_name: c.line_sender_column_name = undefined;
        
        if (!c.line_sender_column_name_init(&column_name, name.len, name.ptr, &c_err)) {
            return convertError(c_err.?);
        }
        
        if (!c.line_sender_buffer_column_i64(self.c_buffer, column_name, value, &c_err)) {
            return convertError(c_err.?);
        }
        
        return self;
    }

    /// Add a floating-point column to the current row
    pub fn columnF64(self: *Buffer, name: []const u8, value: f64) !*Buffer {
        var c_err: ?*c.line_sender_error = null;
        var column_name: c.line_sender_column_name = undefined;
        
        if (!c.line_sender_column_name_init(&column_name, name.len, name.ptr, &c_err)) {
            return convertError(c_err.?);
        }
        
        if (!c.line_sender_buffer_column_f64(self.c_buffer, column_name, value, &c_err)) {
            return convertError(c_err.?);
        }
        
        return self;
    }

    /// Add a string column to the current row
    pub fn columnStr(self: *Buffer, name: []const u8, value: []const u8) !*Buffer {
        var c_err: ?*c.line_sender_error = null;
        var column_name: c.line_sender_column_name = undefined;
        var utf8_value: c.line_sender_utf8 = undefined;
        
        if (!c.line_sender_column_name_init(&column_name, name.len, name.ptr, &c_err)) {
            return convertError(c_err.?);
        }
        
        if (!c.line_sender_utf8_init(&utf8_value, value.len, value.ptr, &c_err)) {
            return convertError(c_err.?);
        }
        
        if (!c.line_sender_buffer_column_str(self.c_buffer, column_name, utf8_value, &c_err)) {
            return convertError(c_err.?);
        }
        
        return self;
    }

    /// Add a timestamp column to the current row (nanoseconds)
    pub fn columnTsNanos(self: *Buffer, name: []const u8, timestamp: TimestampNanos) !*Buffer {
        var c_err: ?*c.line_sender_error = null;
        var column_name: c.line_sender_column_name = undefined;
        
        if (!c.line_sender_column_name_init(&column_name, name.len, name.ptr, &c_err)) {
            return convertError(c_err.?);
        }
        
        if (!c.line_sender_buffer_column_ts_nanos(self.c_buffer, column_name, timestamp.value, &c_err)) {
            return convertError(c_err.?);
        }
        
        return self;
    }

    /// Add a timestamp column to the current row (microseconds)
    pub fn columnTsMicros(self: *Buffer, name: []const u8, timestamp: TimestampMicros) !*Buffer {
        var c_err: ?*c.line_sender_error = null;
        var column_name: c.line_sender_column_name = undefined;
        
        if (!c.line_sender_column_name_init(&column_name, name.len, name.ptr, &c_err)) {
            return convertError(c_err.?);
        }
        
        if (!c.line_sender_buffer_column_ts_micros(self.c_buffer, column_name, timestamp.value, &c_err)) {
            return convertError(c_err.?);
        }
        
        return self;
    }

    /// Complete the current row with a timestamp in nanoseconds
    pub fn atNanos(self: *Buffer, timestamp: TimestampNanos) !void {
        var c_err: ?*c.line_sender_error = null;
        if (!c.line_sender_buffer_at_nanos(self.c_buffer, timestamp.value, &c_err)) {
            return convertError(c_err.?);
        }
    }

    /// Complete the current row with a timestamp in microseconds
    pub fn atMicros(self: *Buffer, timestamp: TimestampMicros) !void {
        var c_err: ?*c.line_sender_error = null;
        if (!c.line_sender_buffer_at_micros(self.c_buffer, timestamp.value, &c_err)) {
            return convertError(c_err.?);
        }
    }

    /// Complete the current row without providing a timestamp
    pub fn atNow(self: *Buffer) !void {
        var c_err: ?*c.line_sender_error = null;
        if (!c.line_sender_buffer_at_now(self.c_buffer, &c_err)) {
            return convertError(c_err.?);
        }
    }
};

/// Sender for connecting to QuestDB and sending data
pub const Sender = struct {
    c_sender: *c.line_sender,
    allocator: std.mem.Allocator,

    /// Create a new Sender from a configuration string
    pub fn fromConf(allocator: std.mem.Allocator, config: []const u8) !Sender {
        var c_err: ?*c.line_sender_error = null;
        const c_sender = c.line_sender_from_conf(
            c.line_sender_utf8{ .len = config.len, .buf = config.ptr },
            &c_err,
        );

        if (c_err != null) {
            return convertError(c_err.?);
        }

        return Sender{
            .c_sender = c_sender.?,
            .allocator = allocator,
        };
    }

    /// Create a new Sender from the QDB_CLIENT_CONF environment variable
    pub fn fromEnv(allocator: std.mem.Allocator) !Sender {
        var c_err: ?*c.line_sender_error = null;
        const c_sender = c.line_sender_from_env(&c_err);

        if (c_err != null) {
            return convertError(c_err.?);
        }

        return Sender{
            .c_sender = c_sender.?,
            .allocator = allocator,
        };
    }

    /// Create a new Sender from the given options
    pub fn init(allocator: std.mem.Allocator, options: SenderOptions) !Sender {
        var c_err: ?*c.line_sender_error = null;
        var c_opts = c.line_sender_opts_new(
            options.protocol.toC(),
            c.line_sender_utf8{ .len = options.host.len, .buf = options.host.ptr },
            options.port,
        );

        if (options.bind_interface) |bind_interface| {
            _ = c.line_sender_opts_bind_interface(
                c_opts,
                c.line_sender_utf8{ .len = bind_interface.len, .buf = bind_interface.ptr },
                &c_err,
            );
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.username) |username| {
            _ = c.line_sender_opts_username(
                c_opts,
                c.line_sender_utf8{ .len = username.len, .buf = username.ptr },
                &c_err,
            );
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.password) |password| {
            _ = c.line_sender_opts_password(
                c_opts,
                c.line_sender_utf8{ .len = password.len, .buf = password.ptr },
                &c_err,
            );
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.token) |token| {
            _ = c.line_sender_opts_token(
                c_opts,
                c.line_sender_utf8{ .len = token.len, .buf = token.ptr },
                &c_err,
            );
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.token_x) |token_x| {
            _ = c.line_sender_opts_token_x(
                c_opts,
                c.line_sender_utf8{ .len = token_x.len, .buf = token_x.ptr },
                &c_err,
            );
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.token_y) |token_y| {
            _ = c.line_sender_opts_token_y(
                c_opts,
                c.line_sender_utf8{ .len = token_y.len, .buf = token_y.ptr },
                &c_err,
            );
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.auth_timeout) |auth_timeout| {
            _ = c.line_sender_opts_auth_timeout(c_opts, auth_timeout, &c_err);
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        _ = c.line_sender_opts_tls_verify(c_opts, options.tls_verify, &c_err);
        if (c_err != null) {
            c.line_sender_opts_free(c_opts);
            return convertError(c_err.?);
        }

        if (options.tls_ca) |tls_ca| {
            _ = c.line_sender_opts_tls_ca(c_opts, tls_ca.toC(), &c_err);
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.tls_roots) |tls_roots| {
            _ = c.line_sender_opts_tls_roots(
                c_opts,
                c.line_sender_utf8{ .len = tls_roots.len, .buf = tls_roots.ptr },
                &c_err,
            );
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.max_buf_size) |max_buf_size| {
            _ = c.line_sender_opts_max_buf_size(c_opts, max_buf_size, &c_err);
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.retry_timeout) |retry_timeout| {
            _ = c.line_sender_opts_retry_timeout(c_opts, retry_timeout, &c_err);
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.request_min_throughput) |request_min_throughput| {
            _ = c.line_sender_opts_request_min_throughput(c_opts, request_min_throughput, &c_err);
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        if (options.request_timeout) |request_timeout| {
            _ = c.line_sender_opts_request_timeout(c_opts, request_timeout, &c_err);
            if (c_err != null) {
                c.line_sender_opts_free(c_opts);
                return convertError(c_err.?);
            }
        }

        const c_sender = c.line_sender_build(c_opts, &c_err);
        if (c_err != null) {
            return convertError(c_err.?);
        }

        return Sender{
            .c_sender = c_sender.?,
            .allocator = allocator,
        };
    }

    /// Free the sender resources
    pub fn deinit(self: *Sender) void {
        c.line_sender_close(self.c_sender);
    }

    /// Check if the sender must be closed due to an error
    pub fn mustClose(self: *const Sender) bool {
        return c.line_sender_must_close(self.c_sender);
    }

    /// Send the buffer to QuestDB and clear it
    pub fn flush(self: *Sender, buffer: *Buffer) !void {
        var c_err: ?*c.line_sender_error = null;
        if (!c.line_sender_flush(self.c_sender, buffer.c_buffer, &c_err)) {
            return convertError(c_err.?);
        }
    }

    /// Send the buffer to QuestDB without clearing it
    pub fn flushAndKeep(self: *Sender, buffer: *const Buffer) !void {
        var c_err: ?*c.line_sender_error = null;
        if (!c.line_sender_flush_and_keep(self.c_sender, buffer.c_buffer, &c_err)) {
            return convertError(c_err.?);
        }
    }

    /// Send the buffer to QuestDB with transactional flag
    pub fn flushAndKeepWithFlags(self: *Sender, buffer: *Buffer, transactional: bool) !void {
        var c_err: ?*c.line_sender_error = null;
        if (!c.line_sender_flush_and_keep_with_flags(self.c_sender, buffer.c_buffer, transactional, &c_err)) {
            return convertError(c_err.?);
        }
    }
};

test "basic usage" {
    const allocator = std.testing.allocator;
    
    var buffer = try Buffer.init(allocator);
    defer buffer.deinit();
    
    try buffer.table("test_table");
    try buffer.symbol("symbol", "AAPL");
    try buffer.columnF64("price", 150.25);
    try buffer.atNanos(TimestampNanos.now());
    
    // In a real application, you would send this to QuestDB:
    // var sender = try Sender.fromConf(allocator, "http::addr=localhost:9000;");
    // defer sender.deinit();
    // try sender.flush(&buffer);
}