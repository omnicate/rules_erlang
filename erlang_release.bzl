load(
    "//private:erlang_release.bzl",
    _erlang_release = "erlang_release",
)

def erlang_release(**kwargs):
    _erlang_release(**kwargs)