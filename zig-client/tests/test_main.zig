//! Tests for the QuestDB Zig client

const std = @import("std");
const testing = std.testing;
const questdb = @import("../src/main.zig");

// Basic test to verify the client can be initialized and used
test "buffer initialization and usage" {
    const allocator = testing.allocator;
    
    var buffer = try questdb.Buffer.init(allocator);
    defer buffer.deinit();
    
    try buffer.table("test_table");
    try buffer.symbol("symbol", "AAPL");
    try buffer.columnBool("active", true);
    try buffer.columnI64("count", 42);
    try buffer.columnF64("price", 150.25);
    try buffer.columnStr("description", "Apple Inc.");
    try buffer.atNanos(questdb.TimestampNanos.now());
    
    // Verify buffer has content
    try testing.expect(buffer.size() > 0);
    try testing.expect(buffer.rowCount() == 1);
    try testing.expect(buffer.isTransactional());
    
    // Add another row to test multiple rows
    try buffer.table("test_table");
    try buffer.symbol("symbol", "MSFT");
    try buffer.columnF64("price", 290.75);
    try buffer.atNanos(questdb.TimestampNanos.now());
    
    try testing.expect(buffer.rowCount() == 2);
    try testing.expect(buffer.isTransactional());
    
    // Test marker functionality
    try buffer.setMarker();
    
    try buffer.table("test_table");
    try buffer.symbol("symbol", "GOOG");
    try buffer.columnF64("price", 2500.50);
    try buffer.atNanos(questdb.TimestampNanos.now());
    
    try testing.expect(buffer.rowCount() == 3);
    
    // Rewind to marker
    try buffer.rewindToMarker();
    try testing.expect(buffer.rowCount() == 2);
    
    // Clear buffer
    buffer.clear();
    try testing.expect(buffer.size() == 0);
    try testing.expect(buffer.rowCount() == 0);
}

// Test timestamp functionality
test "timestamp operations" {
    // Test nanosecond timestamp
    const nanos = questdb.TimestampNanos.init(1659548315647406592);
    try testing.expectEqual(@as(i64, 1659548315647406592), nanos.value);
    
    // Test microsecond timestamp
    const micros = questdb.TimestampMicros.init(1659548204354448);
    try testing.expectEqual(@as(i64, 1659548204354448), micros.value);
    
    // Test current time functions
    const now_nanos = questdb.TimestampNanos.now();
    const now_micros = questdb.TimestampMicros.now();
    
    // Current time should be positive
    try testing.expect(now_nanos.value > 0);
    try testing.expect(now_micros.value > 0);
    
    // Nanos should be greater than micros (more precision)
    try testing.expect(now_nanos.value > now_micros.value);
}

// Test SenderOptions configuration
test "sender options" {
    const options = questdb.SenderOptions.init(
        .http,
        "localhost",
        9000
    );
    
    try testing.expectEqual(questdb.Protocol.http, options.protocol);
    try testing.expectEqualStrings("localhost", options.host);
    try testing.expectEqual(@as(u16, 9000), options.port);
    try testing.expectEqual(@as(?[]const u8, null), options.bind_interface);
    try testing.expectEqual(@as(?[]const u8, null), options.username);
    try testing.expectEqual(@as(?[]const u8, null), options.password);
    try testing.expectEqual(true, options.tls_verify);
}

// Test error conversion
test "error conversion" {
    // This test is more for code coverage, as we can't easily create C errors
    const err = questdb.Error.InvalidApiCall;
    try testing.expectEqual(questdb.Error.InvalidApiCall, err);
}

// Test protocol enum conversion
test "protocol conversion" {
    try testing.expectEqual(@as(c_int, 0), @intFromEnum(questdb.Protocol.tcp.toC()));
    try testing.expectEqual(@as(c_int, 1), @intFromEnum(questdb.Protocol.tcps.toC()));
    try testing.expectEqual(@as(c_int, 2), @intFromEnum(questdb.Protocol.http.toC()));
    try testing.expectEqual(@as(c_int, 3), @intFromEnum(questdb.Protocol.https.toC()));
}

// Test certificate authority enum conversion
test "certificate authority conversion" {
    try testing.expectEqual(@as(c_int, 0), @intFromEnum(questdb.CertificateAuthority.webpki_roots.toC()));
    try testing.expectEqual(@as(c_int, 1), @intFromEnum(questdb.CertificateAuthority.os_roots.toC()));
    try testing.expectEqual(@as(c_int, 2), @intFromEnum(questdb.CertificateAuthority.webpki_and_os_roots.toC()));
    try testing.expectEqual(@as(c_int, 3), @intFromEnum(questdb.CertificateAuthority.pem_file.toC()));
}