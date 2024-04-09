-module(app_file_tool).

-mode(compile).

-export([main/1]).

-spec main([string()]) -> no_return().
main([KeyString, AppSrc]) ->
    Key = list_to_atom(KeyString),
    {ok, Value} = io:read(""),
    {ok, [AppInfo]} = file:consult(AppSrc),
    {application, AppName, Props} = AppInfo,
    NewProps = lists:keystore(Key, 1, Props, {Key, Value}),
    io:format("~tp.~n", [{application, AppName, ensure_relx_compliant(NewProps)}]),
    halt();
main([AppSrc]) ->
    {ok, Entries} = io:read(""),
    {ok, [AppInfo]} = file:consult(AppSrc),
    {application, AppName, Props} = AppInfo,
    NewProps = Props ++ Entries,
    io:format("~tp.~n", [{application, AppName, ensure_relx_compliant(NewProps)}]),
    halt();
main(_) ->
    halt(1).

ensure_relx_compliant(AppData) ->
    ensure_registered(ensure_string_vsn(AppData)).

%% https://github.com/erlware/relx/issues/32
ensure_registered(AppData) ->
    case lists:keyfind(registered, 1, AppData) of
        false ->
            [{registered, []} | AppData];
        {registered, _} ->
            AppData
    end.

%% https://github.com/for-GET/jesse/blob/master/src/jesse.app.src#L4
ensure_string_vsn(AppData) ->
    case proplists:get_value(vsn, AppData, undefined) of
        undefined ->
            AppData;
        VSN when is_atom(VSN)->
            proplists:delete(vsn, AppData) ++ [{vsn, atom_to_list(VSN)}];
        _ ->
            AppData
    end.