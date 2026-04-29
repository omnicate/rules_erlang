-module(umbrella_smoke_SUITE).

-export([all/0, end_per_suite/1, init_per_suite/1, smoke/1]).

all() ->
    [smoke].

init_per_suite(Config) ->
    {ok, _Started} = application:ensure_all_started(greeter_web),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(greeter_web),
    ok = application:stop(greeter),
    ok.

smoke(_Config) ->
    <<"Hello, common_test! via greeter_web">> = greeter_web:message("common_test"),
    ok.
