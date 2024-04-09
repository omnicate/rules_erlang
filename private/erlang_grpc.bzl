load("//:erlang_app_info.bzl", "ErlangAppInfo", "flat_deps")
load("//:util.bzl", "path_join")
load(":util.bzl", "erl_libs_contents")
load(":erlang_bytecode.bzl", "unique_dirnames")
load(
    "//tools:erlang_toolchain.bzl",
    "erlang_dirs",
    "maybe_install_erlang",
)

def _impl(ctx):
    outputs = [
        ctx.actions.declare_file(f.name)
        for f in ctx.attr.outs
    ]

    out_dir = unique_dirnames(outputs)
    if len(out_dir) > 1:
        fail(ctx.attr.outs, "do not share a common parent directory")
    out_dir = out_dir[0]

    erl_libs_dir = ctx.attr.name + "_deps"

    erl_libs_files = erl_libs_contents(
        ctx,
        deps = flat_deps(ctx.attr.deps),
        dir = erl_libs_dir,
    )

    erl_libs_path = path_join(ctx.bin_dir.path, ctx.label.package, erl_libs_dir)

    (erlang_home, _, runfiles) = erlang_dirs(ctx)

    proto_lib = ctx.attr.proto_lib
    proto_files = proto_lib[ProtoInfo].transitive_sources

    script = """#!/bin/bash
set -euo pipefail

{maybe_install_erlang}

export ERL_LIBS=$PWD/{erl_libs_path}

set -x
"{erlang_home}"/bin/erl \\
    -noshell \\
    -eval "grpcbox_gen:from_proto(\\"{proto}\\" , \\"{out_dir}\\")" \\
    -s erlang halt
    """.format(
        proto = ctx.attr.proto,
        erl_libs_path = erl_libs_path,
        out_dir = out_dir,
        maybe_install_erlang = maybe_install_erlang(ctx),
        erlang_home = erlang_home,
    )

    inputs = depset(
        transitive = [depset(erl_libs_files), runfiles.files, proto_files],
    )

    ctx.actions.run_shell(
        command = script,
        inputs =  inputs,
        outputs = outputs,
        mnemonic = "ERLGRPC",
    )

    return [DefaultInfo(files = depset(outputs))]

erlang_grpc = rule(
    implementation = _impl,
    attrs = {
        "proto": attr.string(
            mandatory = True,
            doc = "The path to the .proto file to generate code from.",
        ),
        "proto_lib": attr.label(
            mandatory = True,
            doc = "The proto_library target to generate code from.",
            providers = [ProtoInfo],
        ),
        "deps": attr.label_list(providers = [ErlangAppInfo]),
        "outs": attr.output_list(
            mandatory = True,
        ),
    },
    toolchains = ["//tools:toolchain_type"],
)