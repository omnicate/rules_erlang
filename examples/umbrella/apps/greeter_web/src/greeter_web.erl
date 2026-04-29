-module(greeter_web).

-export([message/1]).

-spec message(string() | binary()) -> binary().
message(Name) ->
    Greeting = greeter:greeting(Name),
    Suffix = application:get_env(greeter_web, greeting_suffix, <<" via greeter_web">>),
    <<Greeting/binary, Suffix/binary>>.
