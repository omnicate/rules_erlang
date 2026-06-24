load(
    "//private:erlang_build.bzl",
    "OtpInfo",
)

def _impl(ctx):
    otpinfo = ctx.attr.otp[OtpInfo]
    vars = {
        "OTP_VERSION": otpinfo.version,
        "ERLANG_HOME": otpinfo.erlang_home,
    }
    if otpinfo.release_dir_tar != None:
        vars["ERLANG_RELEASE_TAR_PATH"] = otpinfo.release_dir_tar.path
        vars["ERLANG_RELEASE_TAR_SHORT_PATH"] = otpinfo.release_dir_tar.short_path
        vars["ERLANG_INSTALL_PATH"] = otpinfo.install_path
    return [
        platform_common.ToolchainInfo(otpinfo = otpinfo),
        platform_common.TemplateVariableInfo(vars),
    ]

erlang_toolchain = rule(
    implementation = _impl,
    attrs = {
        "otp": attr.label(
            mandatory = True,
            providers = [OtpInfo],
        ),
    },
    provides = [
        platform_common.ToolchainInfo,
        platform_common.TemplateVariableInfo,
    ],
)

def _build_info(ctx):
    return ctx.toolchains["//tools:toolchain_type"].otpinfo

def erlang_dirs(ctx, short_path = False):
    """Returns (erlang_home, release_dir_tar, runfiles) for the Erlang toolchain.
    
    Args:
        ctx: The rule context
        short_path: If True, return short_path for release_dir_tar (for runfiles/tests).
                   If False (default), return full path (for build actions).
    
    Returns:
        Tuple of (erlang_home, release_dir_tar, runfiles).
        erlang_home is always the fixed install_path for internal/prebuilt erlang.
    """
    info = _build_info(ctx)
    if info.release_dir_tar != None:
        runfiles = ctx.runfiles([
            info.release_dir_tar,
            info.version_file,
        ])
        # Always use the fixed install_path - this ensures path consistency
        # across all sandboxed actions
        erlang_home = info.erlang_home
    else:
        runfiles = ctx.runfiles([
            info.version_file,
        ])
        # For external erlang, use the absolute path
        erlang_home = info.erlang_home
    return (erlang_home, info.release_dir_tar, runfiles)

def maybe_install_erlang(ctx, short_path = False):
    """Returns shell commands to extract Erlang to the fixed install path.

    For internal/prebuilt Erlang, this extracts the tar to install_path
    atomically: each caller extracts into a unique sibling tmp dir,
    touches a `.ready` sentinel after `tar` succeeds, then renames the
    tmp dir onto install_path. Concurrent losers discard their tmp dir.
    Waiters poll for the sentinel. A stale install_path with no
    sentinel (left behind by an interrupted older wrapper) is healed
    once under a `mkdir` lock.

    Polling on `bin/escript` is not safe because `tar` emits `bin/`
    before `lib/`, so escript can appear before kernel/stdlib are on
    disk.

    Linux-only: relies on `mv -T` and rename(2) returning ENOTEMPTY
    when the target is a non-empty directory.

    Helpers and variables are prefixed `__otp_` to avoid colliding
    with the caller script's namespace.
    """
    info = _build_info(ctx)
    release_dir_tar = info.release_dir_tar
    if release_dir_tar == None:
        return ""
    else:
        return """\
__otp_dir="{install_path}"
__otp_tar="{release_tar}"
__otp_parent="$(dirname "${{__otp_dir}}")"
__otp_ready="${{__otp_dir}}/.ready"
mkdir -p "${{__otp_parent}}"

__otp_extract() {{
    local _tmp
    _tmp="$(mktemp -d -p "${{__otp_parent}}")" || return 1
    if tar --extract --directory "${{_tmp}}" --file "${{__otp_tar}}" \\
        && touch "${{_tmp}}/.ready" \\
        && mv -T "${{_tmp}}" "${{__otp_dir}}" 2>/dev/null; then
        return 0
    fi
    rm -rf "${{_tmp}}"
    return 1
}}

__otp_wait() {{
    local _i
    for _i in $(seq 1 60); do
        [ -f "${{__otp_ready}}" ] && return 0
        sleep 1
    done
    return 1
}}

if [ ! -f "${{__otp_ready}}" ]; then
    __otp_extract || true
    if ! __otp_wait; then
        if mkdir "${{__otp_dir}}.heal" 2>/dev/null; then
            if [ ! -f "${{__otp_ready}}" ]; then
                rm -rf "${{__otp_dir}}"
            fi
            rmdir "${{__otp_dir}}.heal" 2>/dev/null || true
            __otp_extract || true
        fi
        __otp_wait || {{
            echo>&2 "ERROR: OTP install at ${{__otp_dir}} is incomplete (no .ready sentinel)."
            echo>&2 "       Recovery: rm -rf ${{__otp_parent}} and retry."
            exit 1
        }}
    fi
fi

unset -f __otp_extract __otp_wait
unset __otp_dir __otp_tar __otp_parent __otp_ready
export ROOTDIR="{install_path}"\
""".format(
            release_tar = release_dir_tar.short_path if short_path else release_dir_tar.path,
            install_path = info.install_path,
        )

def version_file(ctx):
    info = _build_info(ctx)
    return info.version_file
