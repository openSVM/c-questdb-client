const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a module for the QuestDB client
    const questdb_module = b.addModule("questdb", .{
        .source_file = .{ .path = "src/main.zig" },
    });

    // Create a static library
    const lib = b.addStaticLibrary(.{
        .name = "questdb-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add the C library as a dependency
    lib.addIncludePath(.{ .path = "../include" });
    lib.linkLibC();
    lib.linkSystemLibrary("questdb_client");

    // Install the library
    b.installArtifact(lib);

    // Create a test executable
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "tests/test_main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add the C library as a dependency for tests
    main_tests.addIncludePath(.{ .path = "../include" });
    main_tests.linkLibC();
    main_tests.linkSystemLibrary("questdb_client");

    // Create a test step
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    // Create an example executable
    const example = b.addExecutable(.{
        .name = "questdb-example",
        .root_source_file = .{ .path = "examples/example.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add the QuestDB module to the example
    example.addModule("questdb", questdb_module);
    
    // Add the C library as a dependency for the example
    example.addIncludePath(.{ .path = "../include" });
    example.linkLibC();
    example.linkSystemLibrary("questdb_client");

    // Install the example
    b.installArtifact(example);

    // Create a run step for the example
    const run_example = b.addRunArtifact(example);
    if (b.args) |args| {
        run_example.addArgs(args);
    }

    const run_step = b.step("run-example", "Run the example");
    run_step.dependOn(&run_example.step);
}