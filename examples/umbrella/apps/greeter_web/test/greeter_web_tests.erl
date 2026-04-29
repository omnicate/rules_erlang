-module(greeter_web_tests).

-include_lib("eunit/include/eunit.hrl").

message_test() ->
    ?assertEqual(
        <<"Hello, umbrella! via greeter_web">>,
        greeter_web:message("umbrella")
    ).
