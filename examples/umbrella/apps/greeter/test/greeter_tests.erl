-module(greeter_tests).

-include_lib("eunit/include/eunit.hrl").

greeting_test() ->
    ?assertEqual(<<"Hello, umbrella!">>, greeter:greeting("umbrella")).
