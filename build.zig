const std = @import("std");
const protobuf = @import("protobuf");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = false,
        .omit_frame_pointer = false,
    });
    lib_mod.addImport("protobuf", protobuf_dep.module("protobuf"));

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "sentence_piece_zig",
        .root_module = lib_mod,
    });
    lib.linker_allow_shlib_undefined = true;

    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("sentence_piece_zig_lib", lib_mod);
    exe_mod.addImport("protobuf", protobuf_dep.module("protobuf"));

    const exe = b.addExecutable(.{
        .name = "sentence_piece_zig",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // Different commands

    const protoc_step = protobuf.RunProtocStep.create(b, protobuf_dep.builder, target, .{
        .destination_directory = b.path("src/"),
        .source_files = &.{
            "src/sentencepiece_model.proto",
        },
        .include_directories = &.{},
    });
    const gen_proto = b.step("gen-proto", "generates zig files from protocol buffer definitions");
    gen_proto.dependOn(&protoc_step.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // const python_wrapper_module = b.createModule(.{
    //     .root_source_file = b.path("zentencepiecemodule.zig"),
    //     .optimize = optimize,
    //     .target = target,
    //     .strip = false,
    //     .omit_frame_pointer = false,
    // });
    // python_wrapper_module.addImport("sentence_piece_zig_lib", lib_mod);
    // const wrapper_lib = b.addSharedLibrary(.{
    //     .name = "zentencepiece",
    //     .root_module = python_wrapper_module,
    //     .version = .{ .major = 1, .minor = 2, .patch = 3 },
    // });
    // wrapper_lib.linkLibC();
    // const include_dirs = b.option([]const u8, "include_dirs", "Comma-separated list of include directories");
    // if (include_dirs) |includes_str| {
    //     var tokenizer = std.mem.tokenizeSequence(u8, includes_str, ",");
    //     while (tokenizer.next()) |path| {
    //         wrapper_lib.addIncludePath(std.Build.LazyPath{ .cwd_relative = path });
    //     }
    // }
    // b.installArtifact(wrapper_lib);

    // const build_python_wrapper_step = b.step("build-python", "Build the Python wrapper");
    // build_python_wrapper_step.dependOn(&wrapper_lib.step);
}
