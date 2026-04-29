# Umbrella Erlang Example

This example shows a small umbrella-style layout built with `rules_erlang`:

- `apps/greeter`: a library app with an eunit test
- `apps/greeter_web`: an app that depends on `greeter`, has eunit and common_test coverage, and is the release entrypoint
- `release.bzl`: example-local relx/release helpers used to build a release directory and OCI image
- `MODULE.bazel`: pins a prebuilt OTP 28.5 toolchain from `gleam-community/erlang-linux-builds`

The compile, `extract_app`, xref, eunit, common_test, dialyzer, relx release, and image targets are all intentionally explicit so the example can be copied into another repo.

`rules_erlang` does not currently ship a public relx/image rule.
This example therefore keeps the release helpers local to the example package while still using the normal `rules_erlang` app/test rules for everything else.

The example uses the static Linux OTP archives from `gleam-community/erlang-linux-builds`, so it does not depend on a host Erlang installation.

## Standard workflow

Run these commands from `examples/umbrella/`.

Run the static checks and tests:

```sh
bazel test //:checks
```

Build the release directory:

```sh
bazel build //:umbrella_release
```

Build a Docker-loadable OCI tarball:

```sh
bazel build //:umbrella_image.tar
docker load -i bazel-bin/umbrella_image_tarball/tarball.tar
docker run --rm rules-erlang/umbrella-example:latest
```

## Interactive shell

Start a shell with both apps and their test beams on the code path:

```sh
bazel run //:repl
```

Then in the Erlang shell:

```erlang
greeter:greeting("umbrella").
greeter_web:message("umbrella").
application:ensure_all_started(greeter_web).
```
