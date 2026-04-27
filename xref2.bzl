load(
    "//private:xref2.bzl",
    "xref_query",
    "xref_test",
)
XREF_TAG = "xref"

def xref(
        name = "xref",
        target = ":erlang_app",
        size = "small",
        tags = [],
        **kwargs):
    xref_test(
        name = name,
        target = target,
        size = size,
        tags = tags + [XREF_TAG],
        **kwargs
    )
    xref_query(
        name = name + "-query",
        testonly = True,
        target = target,
        tags = tags,
        **kwargs
    )
