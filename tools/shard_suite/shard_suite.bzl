load("//private:erlang_bytecode.bzl", "erlang_bytecode")
load("//private:escript_flat.bzl", "escript_flat")
load("//tools:erlang.bzl", "DEFAULT_LABEL")

def shard_suite(erlang_version_label = DEFAULT_LABEL):
    erlang_bytecode(
        name = "beam-{}".format(erlang_version_label),
        dest = "alt",
        erlang_installation = Label("//tools:otp-{}-installation".format(erlang_version_label)),
        srcs = [
            "src/shard_suite.erl",
        ],
    )

    escript_flat(
        name = "escript-{}".format(erlang_version_label),
        erlang_installation = Label("//tools:otp-{}-installation".format(erlang_version_label)),
        beam = [":beam-{}".format(erlang_version_label)],
        visibility = ["//visibility:public"],
    )
