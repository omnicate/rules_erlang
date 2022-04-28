load("//private:shell.bzl", "shell_private")
load("//tools:erlang.bzl", "DEFAULT_LABEL")

def shell(
        erlang_version_label = DEFAULT_LABEL,
        **kwargs):
    shell_private(
        erlang_installation = Label("//tools:otp-{}-installation".format(erlang_version_label)),
        is_windows = select({
            "@bazel_tools//src/conditions:host_windows": True,
            "//conditions:default": False,
        }),
        **kwargs
    )
