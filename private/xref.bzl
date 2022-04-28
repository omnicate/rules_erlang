load("//:erlang_app_info.bzl", "ErlangAppInfo")
load(
    "//:util.bzl",
    "path_join",
    "windows_path",
)
load(":ct.bzl", "code_paths")
load(
    ":erlang_installation.bzl",
    "ErlangInstallationInfo",
    "erlang_dirs",
    "maybe_symlink_erlang",
)

def _to_erlang_string_list(strings):
    return "[" + ",".join(["\"{}\"".format(s) for s in strings]) + "]"

def _to_erlang_atom_list(strings):
    return "[" + ",".join(strings) + "]"

def _impl(ctx):
    lib_info = ctx.attr.target[ErlangAppInfo]

    extra_paths = []
    dirs = [path_join(ctx.attr.target.label.package, "ebin")]
    for dep in lib_info.deps + ctx.attr.additional_libs:
        if dep.label.workspace_root != "":
            extra_paths.extend(code_paths(dep))
        else:
            dirs.append(path_join(dep.label.package, "ebin"))

    xref_config = "[{xref, ["
    xref_config = xref_config + "{config, #{"
    xref_config = xref_config + "extra_paths => " + _to_erlang_string_list(extra_paths)
    xref_config = xref_config + ", "
    xref_config = xref_config + "dirs => " + _to_erlang_string_list(dirs)
    xref_config = xref_config + "}}"
    xref_config = xref_config + ", "
    xref_config = xref_config + "{checks, " + _to_erlang_atom_list(ctx.attr.checks) + "}"
    xref_config = xref_config + "]}]."
    xref_config = xref_config + "\n"

    config_file = ctx.actions.declare_file("xref.config")
    ctx.actions.write(
        output = config_file,
        content = xref_config,
    )

    xrefr_path = path_join(
        ctx.attr._xrefr.label.workspace_root,
        ctx.file._xrefr.short_path,
    )

    (erlang_home, _, runfiles) = erlang_dirs(ctx)

    if not ctx.attr.is_windows:
        output = ctx.actions.declare_file(ctx.label.name)
        script = """set -euo pipefail

{maybe_symlink_erlang}

export HOME=${{TEST_TMPDIR}}

"{erlang_home}"/bin/erl \\
    -eval '{{ok, [C]}} = file:consult("{config_path}"), io:format("~p~n", [C]), halt().' \\
    -noshell

set -x
"{erlang_home}"/bin/escript $TEST_SRCDIR/$TEST_WORKSPACE/{xrefr} \\
    --config {config_path}
""".format(
            maybe_symlink_erlang = maybe_symlink_erlang(ctx, short_path = True),
            erlang_home = erlang_home,
            xrefr = xrefr_path,
            config_path = config_file.short_path,
        )
    else:
        output = ctx.actions.declare_file(ctx.label.name + ".bat")
        script = """@echo off
REM TEST_SRCDIR is provided by bazel but with unix directory separators
set xrefr=%TEST_SRCDIR%/%TEST_WORKSPACE%/{xrefr}
set xrefr=%xrefr:/=\\%
echo on
"{erlang_home}\\bin\\escript" %xrefr% ^
    --config {config_path} || exit /b 1
""".format(
            erlang_home = windows_path(erlang_home),
            xrefr = xrefr_path,
            config_path = windows_path(config_file.short_path),
        )

    ctx.actions.write(
        output = output,
        content = script,
    )

    runfiles = ctx.runfiles([
        ctx.file._xrefr,
        config_file,
    ]).merge_all([
        runfiles,
        ctx.attr.target[DefaultInfo].default_runfiles,
    ] + [
        dep[DefaultInfo].default_runfiles
        for dep in ctx.attr.additional_libs
    ])
    return [DefaultInfo(
        runfiles = runfiles,
        executable = output,
    )]

xref_test = rule(
    implementation = _impl,
    attrs = {
        "erlang_installation": attr.label(
            mandatory = True,
            providers = [ErlangInstallationInfo],
        ),
        "_xrefr": attr.label(
            default = Label("@xrefr//file"),
            executable = True,
            cfg = "target",
            allow_single_file = True,
        ),
        "is_windows": attr.bool(mandatory = True),
        "target": attr.label(
            providers = [ErlangAppInfo],
            mandatory = True,
        ),
        "checks": attr.string_list(
            default = [
                "undefined_function_calls",
                "locals_not_used",
                "deprecated_function_calls",
            ],
        ),
        "additional_libs": attr.label_list(
            providers = [ErlangAppInfo],
        ),
    },
    test = True,
)
