# Getting Started with Zig

## Building and depending on this library
* To begin with, we suggest first building the library to ensure you have all
  the tooling and build dependencies set up just right by following the
  [build instructions](BUILD.md)
* Then read the guide for including this library as a
  [dependency from your project](DEPENDENCY.md).

## Prerequisites
* Zig compiler (version 0.14.0 or later)
* CMake (version 4.0.0 or later)
* QuestDB server (version 8.2.3 or later) for testing

## Complete Examples

* [Basic example in Zig](../zig-client/examples/example.zig).

## API Overview

### Connecting

```zig
const std = @import("std");
const questdb = @import("questdb");

// Initialize allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

// Connect using a configuration string
var sender = try questdb.Sender.fromConf(allocator, "http::addr=localhost:9000;");
defer sender.deinit();

// Or connect using environment variable
// var sender = try questdb.Sender.fromEnv(allocator);
// defer sender.deinit();

// Or connect using options
// var options = questdb.SenderOptions.init(.http, "localhost", 9000);
// var sender = try questdb.Sender.init(allocator, options);
// defer sender.deinit();
```

See the main [client libraries](https://questdb.io/docs/reference/clients/overview/)
documentation for the full config string params, including authentication, TLS, etc.

### Building Messages

The `Sender` object is responsible for connecting to the network and
sending data.

Use the `Buffer` type to construct messages (aka rows, aka records,
aka lines).

To avoid malformed messages, this object's methods must be called in a specific order.

For each row, you need to specify a table name and at least one symbol or
column. Symbols must be specified before columns.

You can accumulate multiple lines (rows) with a given buffer and a buffer is
re-usable, but a buffer may only be flushed via the sender after a call to
`buffer.atNanos(..)` (preferred) or `buffer.atNow()`.

```zig
// Create a buffer
var buffer = try questdb.Buffer.init(allocator);
defer buffer.deinit();

// Add a row
try buffer.table("trades");
try buffer.symbol("symbol", "ETH-USD");
try buffer.columnF64("price", 2615.54);
try buffer.atNanos(questdb.TimestampNanos.now());

// Add another row
try buffer.table("trades");
try buffer.symbol("symbol", "BTC-USD");
try buffer.columnF64("price", 42350.25);
try buffer.atNanos(questdb.TimestampNanos.now());

// Send the data to QuestDB
try sender.flush(&buffer);
```

Diagram of valid call order of the buffer API.

![Sequential Coupling](../api_seq/seq.svg)

## Error handling

In the Zig API, functions that can result in errors return error unions that you can handle with Zig's error handling mechanisms.

```zig
// Using try
try buffer.table("trades");
try buffer.symbol("symbol", "ETH-USD");
try buffer.columnF64("price", 2615.54);
try buffer.atNanos(questdb.TimestampNanos.now());

// Or using if-else
if (buffer.atNow()) |_| {
    std.debug.print("Row completed successfully\n", .{});
} else |err| {
    std.debug.print("Error: {}\n", .{err});
    return;
}
```

## Transaction-like behavior with markers

The Buffer API provides a way to mark a point in the buffer and rewind to it if needed, providing transaction-like behavior:

```zig
// Set a marker after some operations
try buffer.setMarker();

// Perform more operations
try buffer.table("trades");
try buffer.symbol("symbol", "BTC-USD");
try buffer.columnF64("price", 42350.25);
try buffer.atNanos(questdb.TimestampNanos.now());

// If something goes wrong, rewind to the marker
try buffer.rewindToMarker();

// When done with the marker, clear it
buffer.clearMarker();
```

## Timestamps

The Zig client provides two timestamp types:

```zig
// Nanosecond precision
const nanos = questdb.TimestampNanos.init(1659548315647406592);
// Or get current time
const now_nanos = questdb.TimestampNanos.now();

// Microsecond precision
const micros = questdb.TimestampMicros.init(1659548204354448);
// Or get current time
const now_micros = questdb.TimestampMicros.now();
```

## Further Topics

* [Data quality and threading considerations](CONSIDERATIONS.md)
* [Authentication and TLS encryption](SECURITY.md)