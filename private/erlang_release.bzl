load("//:erlang_app_info.bzl", "ErlangAppInfo", "flat_deps")
load("//:util.bzl", "path_join")
load(":util.bzl", "erl_libs_contents")
load(
    "//tools:erlang_toolchain.bzl",
    "erlang_dirs",
    "maybe_install_erlang",
)

def _impl(ctx):
    erl_libs_dir = ctx.attr.name + "_deps"

    erl_libs_files = erl_libs_contents(
        ctx,
        deps = flat_deps(ctx.attr.deps),
        dir = erl_libs_dir,
    )

    erl_libs_path = path_join(ctx.bin_dir.path, ctx.label.package, erl_libs_dir)
    out_dir = path_join(ctx.bin_dir.path, ctx.label.package)

    (erlang_home, _, runfiles) = erlang_dirs(ctx)

    output = ctx.actions.declare_file(ctx.attr.out)

    script = """#!/bin/bash
set -euo pipefail

{maybe_install_erlang}

export ERL_LIBS=$PWD/{erl_libs_path}
export LIBDIR="{erl_libs_path}"
export OUTDIR="{out_dir}"

set -x
"{erlang_home}"/bin/erl \\
    -noshell \\
    -eval "{release_fun}" \\
    -s erlang halt > /dev/null
    """.format(
        erl_libs_path = erl_libs_path,
        release_fun = ctx.attr.release_fun,
        out_dir = out_dir,
        maybe_install_erlang = maybe_install_erlang(ctx),
        erlang_home = erlang_home,
    )

    ctx.actions.run_shell(
        command = script,
        inputs = erl_libs_files,
        outputs = [output],
        mnemonic = "ERLRELEASE",
    )


    return [DefaultInfo(files = depset([output]))]

erlang_release = rule(
    implementation = _impl,
    attrs = {
        "release_fun": attr.string(),
        "deps": attr.label_list(providers = [ErlangAppInfo]),
        "out": attr.string(),
    },
    toolchains = ["//tools:toolchain_type"],
)
