"""Example-local relx helpers for the umbrella example."""

load("@rules_erlang//:erlang_app_info.bzl", "ErlangAppInfo", "flat_deps")
load("@rules_erlang//:util.bzl", "path_join")
load("@rules_erlang//private:util.bzl", "erl_libs_contents")
load(
    "@rules_erlang//tools:erlang_toolchain.bzl",
    "erlang_dirs",
    "maybe_install_erlang",
)

ErlangRelxConfigInfo = provider(
    fields = {
        "needed_deps": "Files needed when building the release.",
        "output_dir": "Directory where relx writes the release.",
        "release_name": "Name of the generated release.",
    },
)

def _format_relx_config(
        release_name,
        release_version,
        apps,
        include_erts,
        include_src,
        sys_config_src):
    quoted_apps = ",\n      ".join(apps)
    return """\
[
  {{release, {{{release_name}, "{release_version}"}},
    [
      {apps}
    ]}},
  {{lib_dirs, [
      "@@RELX_LIB_DIR@@"
    ]}},
  {{output_dir, "@@OUTPUT_DIR@@"}},
  {{include_erts, {include_erts}}},
  {{include_src, {include_src}}},
  {{extended_start_script, true}},
  {{sys_config_src, {sys_config_src}}}
]
""".format(
        apps = quoted_apps,
        include_erts = "true" if include_erts else "false",
        include_src = "true" if include_src else "false",
        release_name = release_name,
        release_version = release_version,
        sys_config_src = '"%s"' % sys_config_src.path if sys_config_src else "undefined",
    )

def _relx_config_impl(ctx):
    output_dir = path_join(ctx.bin_dir.path, ctx.label.package, ctx.label.name + "_out")
    output = ctx.actions.declare_file(ctx.label.name + ".relx.config")
    content = _format_relx_config(
        release_name = ctx.attr.release_name,
        release_version = ctx.attr.release_version,
        apps = ctx.attr.apps,
        include_erts = ctx.attr.include_erts,
        include_src = ctx.attr.include_src,
        sys_config_src = ctx.file.sys_config_src,
    )

    ctx.actions.write(
        output = output,
        content = content,
    )

    needed_deps = [ctx.file.sys_config_src] if ctx.file.sys_config_src else []

    return [
        ErlangRelxConfigInfo(
            needed_deps = needed_deps,
            output_dir = output_dir,
            release_name = ctx.attr.release_name,
        ),
        DefaultInfo(files = depset([output])),
    ]

erlang_relx_config = rule(
    implementation = _relx_config_impl,
    attrs = {
        "apps": attr.string_list(mandatory = True),
        "include_erts": attr.bool(default = True),
        "include_src": attr.bool(default = False),
        "release_name": attr.string(mandatory = True),
        "release_version": attr.string(default = "0.1.0"),
        "sys_config_src": attr.label(allow_single_file = True),
    },
    provides = [ErlangRelxConfigInfo],
)

def _release_impl(ctx):
    erl_libs_dir = ctx.attr.name + "_deps"
    relx_libs_dir = ctx.attr.name + "_relx"

    erl_libs_files = erl_libs_contents(
        ctx,
        deps = flat_deps(ctx.attr.deps),
        dir = erl_libs_dir,
    )

    relx_files = erl_libs_contents(
        ctx,
        deps = flat_deps([ctx.attr.relx]),
        dir = relx_libs_dir,
    )

    erl_libs_path = path_join(ctx.bin_dir.path, ctx.label.package, erl_libs_dir)
    relx_libs_path = path_join(ctx.bin_dir.path, ctx.label.package, relx_libs_dir)

    (erlang_home, _, runfiles) = erlang_dirs(ctx)

    output = ctx.actions.declare_directory(ctx.attr.name)
    relx_config = ctx.attr.relx_config
    relx_config_template = relx_config[DefaultInfo].files.to_list()[0]
    relx_config_file = ctx.actions.declare_file(ctx.label.name + ".relx.config")
    ctx.actions.expand_template(
        template = relx_config_template,
        output = relx_config_file,
        substitutions = {
            "@@OUTPUT_DIR@@": relx_config[ErlangRelxConfigInfo].output_dir,
            "@@RELX_LIB_DIR@@": relx_libs_path,
        },
    )
    release_name = relx_config[ErlangRelxConfigInfo].release_name
    relx_release_dir = path_join(
        relx_config[ErlangRelxConfigInfo].output_dir,
        release_name,
    )

    inputs = depset(
        direct = erl_libs_files + relx_files + [relx_config_file] + relx_config[ErlangRelxConfigInfo].needed_deps,
        transitive = [runfiles.files],
    )

    script = """#!/usr/bin/env bash
set -euo pipefail

{maybe_install_erlang}

export ERL_LIBS="$PWD/{relx_libs_path}:$PWD/{erl_libs_path}"

"{erlang_home}"/bin/erl \
  -noshell \
  -eval "relx:build_release({release_name}, $(cat {relx_config_file}))" \
  -s erlang halt > /dev/null

rm -rf "{output}"
mv "{relx_release_dir}" "{output}"
chmod -R u+w "{output}"
""".format(
        maybe_install_erlang = maybe_install_erlang(ctx),
        erl_libs_path = erl_libs_path,
        erlang_home = erlang_home,
        output = output.path,
        release_name = release_name,
        relx_config_file = relx_config_file.path,
        relx_libs_path = relx_libs_path,
        relx_release_dir = relx_release_dir,
    )

    ctx.actions.run_shell(
        command = script,
        inputs = inputs,
        mnemonic = "ExampleErlangRelease",
        outputs = [output],
    )

    return [DefaultInfo(files = depset([output]))]

erlang_release = rule(
    implementation = _release_impl,
    attrs = {
        "deps": attr.label_list(providers = [ErlangAppInfo]),
        "relx": attr.label(
            default = "@erlang_packages//relx",
            providers = [ErlangAppInfo],
        ),
        "relx_config": attr.label(
            mandatory = True,
            providers = [DefaultInfo, ErlangRelxConfigInfo],
        ),
    },
    toolchains = ["@rules_erlang//tools:toolchain_type"],
)
