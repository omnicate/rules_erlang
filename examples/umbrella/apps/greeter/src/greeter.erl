-module(greeter).

-export([greeting/1]).

-spec greeting(string() | binary()) -> binary().
greeting(Name) when is_list(Name) ->
    greeting(unicode:characters_to_binary(Name));
greeting(Name) when is_binary(Name) ->
    <<"Hello, ", Name/binary, "!">>.
