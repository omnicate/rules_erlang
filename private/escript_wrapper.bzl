load(
    "//private:erlang_build.bzl",
    "OtpInfo",
)

# Resolve a File to a runfiles-relative ("rlocation") path. Files in the
# main repo are addressed as "<workspace>/<short_path>"; files coming from
# external repos already carry a leading "../<canonical_repo>/" in their
# short_path, which rlocation expects without the "../".
def _rlocation_path(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return ctx.workspace_name + "/" + file.short_path

# The launcher must work in two distinct contexts:
#   1. Runtime  - bazel run / sh_test / sh_binary `data` dep. RUNFILES_DIR
#                 (or a manifest) is set; resolve files via rlocation.
#   2. Action   - ctx.actions.run(executable = ...) e.g. compile_many.
#                 No runfiles tree, no RUNFILES_DIR; the action's input
#                 tree exposes files at their exec-root paths and PWD is
#                 the exec root, so relative exec paths resolve directly.
# The bootstrap below is a tolerant variant of the canonical
# @bazel_tools//tools/bash/runfiles initializer: if the bash runfiles
# library can't be sourced it installs a stub `rlocation` returning
# empty, and `_resolve` then falls back to the baked-in exec path.
_RUNFILES_BOOTSTRAP = """\
# --- begin tolerant runfiles.bash initializer ---
set -uo pipefail; set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$0.runfiles/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  true
f=; set -e
if ! declare -F rlocation >/dev/null 2>&1; then
  rlocation() { return 1; }
fi
# --- end tolerant runfiles.bash initializer ---

# Resolve a file path: prefer rlocation (runtime context), fall back to
# the baked-in exec-root path (action context).
_resolve() {
  local rloc="$1" execpath="$2" out=""
  out="$(rlocation "${rloc}" 2>/dev/null || true)"
  if [[ -n "${out}" && -e "${out}" ]]; then
    printf '%s' "${out}"
    return 0
  fi
  if [[ -e "${execpath}" ]]; then
    printf '%s' "${execpath}"
    return 0
  fi
  return 1
}\
"""

def _impl(ctx):
    info = ctx.toolchains["//tools:toolchain_type"].otpinfo

    escript_rloc = _rlocation_path(ctx, ctx.file.escript)
    escript_exec = ctx.file.escript.path
    version_rloc = _rlocation_path(ctx, info.version_file)
    version_exec = info.version_file.path

    runfiles_inputs = [ctx.file.escript, info.version_file]

    if info.release_dir_tar != None:
        # Internal/prebuilt erlang: ship the OTP release tar in runfiles
        # and extract it to the fixed `install_path` baked into OtpInfo.
        # This is the same target directory that `maybe_install_erlang`
        # uses, so multiple rules share one extraction (and one cache hit
        # is enough across the whole build).
        #
        # erlang_home_suffix is the path inside `install_path` where the
        # OTP root lives ("/lib/erlang" for source-built OTP, "" for
        # prebuilt). Computed at analysis time from OtpInfo so we don't
        # have to probe the tarball at runtime.
        if not info.erlang_home.startswith(info.install_path):
            fail("erlang_home (%s) is not under install_path (%s); " %
                 (info.erlang_home, info.install_path) +
                 "escript_wrapper cannot derive ERLANG_HOME suffix.")
        erlang_home_suffix = info.erlang_home[len(info.install_path):]

        tar_rloc = _rlocation_path(ctx, info.release_dir_tar)
        tar_exec = info.release_dir_tar.path
        runfiles_inputs.append(info.release_dir_tar)
        otp_setup = """\
OTP_TAR="$(_resolve '{tar_rloc}' '{tar_exec}')" || \\
    {{ echo>&2 "ERROR: OTP release tar not found (rloc='{tar_rloc}', exec='{tar_exec}')"; exit 1; }}
OTP_DIR="{install_path}"
# mkdir(2) is the lock; whoever wins extracts. Same convention as
# rules_erlang's `maybe_install_erlang`, so the cache is shared with
# other rules. Portable across GNU and BSD coreutils (no `mv
# --no-target-directory`, no `find -executable`).
mkdir -p "$(dirname "${{OTP_DIR}}")"
if mkdir "${{OTP_DIR}}" 2>/dev/null; then
    tar --extract --directory "${{OTP_DIR}}" --file "${{OTP_TAR}}"
fi
ERLANG_HOME="${{OTP_DIR}}{erlang_home_suffix}"
ESCRIPT_BIN="${{ERLANG_HOME}}/bin/escript"
# Wait briefly for a concurrent extractor (lost the mkdir race) to
# finish writing bin/escript, mirroring `maybe_install_erlang`'s
# implicit assumption that "directory exists" means "extraction in
# progress or done".
for _ in $(seq 1 60); do
    [[ -x "${{ESCRIPT_BIN}}" ]] && break
    sleep 1
done
[[ -x "${{ESCRIPT_BIN}}" ]] || \\
    {{ echo>&2 "ERROR: ${{ESCRIPT_BIN}} not found or not executable after extraction"; exit 1; }}\
""".format(
            tar_rloc = tar_rloc,
            tar_exec = tar_exec,
            install_path = info.install_path,
            erlang_home_suffix = erlang_home_suffix,
        )
    else:
        # External erlang: rely on the toolchain-provided absolute
        # erlang_home. Nothing to extract; just point ESCRIPT_BIN at it.
        otp_setup = """\
ERLANG_HOME="{erlang_home}"
ESCRIPT_BIN="${{ERLANG_HOME}}/bin/escript"
[[ -x "${{ESCRIPT_BIN}}" ]] || \\
    {{ echo>&2 "ERROR: ${{ESCRIPT_BIN}} not found or not executable"; exit 1; }}\
""".format(erlang_home = info.erlang_home)

    script = """\
#!/usr/bin/env bash
{bootstrap}

set -euo pipefail

ESCRIPT="$(_resolve '{escript_rloc}' '{escript_exec}')" || \\
    {{ echo>&2 "ERROR: escript not found (rloc='{escript_rloc}', exec='{escript_exec}')"; exit 1; }}

VERSION_FILE="$(_resolve '{version_rloc}' '{version_exec}')" || VERSION_FILE=""

{otp_setup}

exec env ERLANG_HOME="${{ERLANG_HOME}}" \\
         VERSION_FILE="${{VERSION_FILE}}" \\
    "${{ESCRIPT_BIN}}" "${{ESCRIPT}}" "$@"
""".format(
        bootstrap = _RUNFILES_BOOTSTRAP,
        escript_rloc = escript_rloc,
        escript_exec = escript_exec,
        version_rloc = version_rloc,
        version_exec = version_exec,
        otp_setup = otp_setup,
    )

    ctx.actions.write(
        output = ctx.outputs.out,
        content = script,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = runfiles_inputs).merge(
        ctx.attr._bash_runfiles[DefaultInfo].default_runfiles,
    )

    return [
        DefaultInfo(
            runfiles = runfiles,
            executable = ctx.outputs.out,
        ),
    ]

escript_wrapper = rule(
    implementation = _impl,
    attrs = {
        "escript": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "out": attr.output(
            mandatory = True,
        ),
        "_bash_runfiles": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
    toolchains = ["//tools:toolchain_type"],
    executable = True,
)
