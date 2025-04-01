//! Example usage of the QuestDB Zig client

const std = @import("std");
const questdb = @import("questdb");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a buffer to accumulate data
    var buffer = try questdb.Buffer.init(allocator);
    defer buffer.deinit();

    // Add a row to the buffer
    try buffer.table("trades");
    try buffer.symbol("symbol", "ETH-USD");
    try buffer.columnF64("price", 2615.54);
    try buffer.columnI64("quantity", 10);
    try buffer.columnBool("is_buy", true);
    try buffer.atNanos(questdb.TimestampNanos.now());

    // Add another row to the buffer
    try buffer.table("trades");
    try buffer.symbol("symbol", "BTC-USD");
    try buffer.columnF64("price", 42350.25);
    try buffer.columnI64("quantity", 2);
    try buffer.columnBool("is_buy", false);
    try buffer.atNanos(questdb.TimestampNanos.now());

    // Print buffer information
    std.debug.print("Buffer contains {} rows\n", .{buffer.rowCount()});
    std.debug.print("Buffer size: {} bytes\n", .{buffer.size()});
    std.debug.print("Buffer is transactional: {}\n", .{buffer.isTransactional()});

    // In a real application, you would connect to QuestDB and send the data:
    // 
    // var sender = try questdb.Sender.fromConf(allocator, "http::addr=localhost:9000;");
    // defer sender.deinit();
    // try sender.flush(&buffer);
    //
    // std.debug.print("Data sent to QuestDB successfully!\n", .{});

    // Demonstrate error handling with a try/catch block
    std.debug.print("\nDemonstrating error handling:\n", .{});
    buffer.clear();
    try buffer.table("trades");
    try buffer.symbol("symbol", "ETH-USD");
    
    // Intentionally skip adding a timestamp to demonstrate error handling
    if (buffer.atNow()) |_| {
        std.debug.print("Row completed successfully\n", .{});
    } else |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    }

    // Demonstrate using markers for transaction-like behavior
    std.debug.print("\nDemonstrating markers for transaction-like behavior:\n", .{});
    buffer.clear();
    
    // Start adding rows
    try buffer.table("trades");
    try buffer.symbol("symbol", "ETH-USD");
    try buffer.columnF64("price", 2615.54);
    try buffer.atNanos(questdb.TimestampNanos.now());
    
    // Set a marker after the first row
    try buffer.setMarker();
    std.debug.print("Marker set after first row\n", .{});
    
    // Add a second row
    try buffer.table("trades");
    try buffer.symbol("symbol", "BTC-USD");
    try buffer.columnF64("price", 42350.25);
    try buffer.atNanos(questdb.TimestampNanos.now());
    
    std.debug.print("Added second row, buffer now has {} rows\n", .{buffer.rowCount()});
    
    // Rewind to marker (simulating a rollback)
    try buffer.rewindToMarker();
    std.debug.print("Rewound to marker, buffer now has {} rows\n", .{buffer.rowCount()});
    
    // Clear marker
    buffer.clearMarker();
    std.debug.print("Marker cleared\n", .{});
}