-module(coverdata_to_lcov).

-mode(compile).

-export([main/1]).

-spec main([string()]) -> no_return().

main([CoverdataFile, LcovFile]) ->
    ScriptName = filename:basename(escript:script_name()),
    io:format(standard_error, "~s: converting ~s to lcov...~n",
              [ScriptName, CoverdataFile]),

    AppsDirPaths = string:split(os:getenv("COVERDATA_TO_LCOV_APPS_DIRS", "apps"), ":"),

    ExecRoot = os:getenv("ROOT"),

    %% When COVERDATA_TO_LCOV_USE_MODULE_INFO is set to a non-empty value
    %% the source path stamped into each module's compile info (available
    %% in beams built with debug_info) is used instead of globbing under
    %% AppsDirPaths. Requires the modules themselves to be loadable in the
    %% running VM (e.g. via ERL_LIBS or -pa pointing at the release lib).
    %% Optionally COVERDATA_TO_LCOV_SOURCE_PREFIX names a substring; the
    %% emitted SF: path is sliced to start at that substring (so e.g. an
    %% absolute sandbox path becomes workspace-relative), and modules whose
    %% recovered path doesn't contain it are skipped.
    UseModuleInfo = os:getenv("COVERDATA_TO_LCOV_USE_MODULE_INFO", "") =/= "",
    SourcePrefix = os:getenv("COVERDATA_TO_LCOV_SOURCE_PREFIX", ""),

    ok = cover:import(CoverdataFile),
    Modules = cover:imported_modules(),

    {ok, S} = file:open(LcovFile, [write]),
    lists:foreach(
      fun (Module) ->
              SFResult = case UseModuleInfo of
                             true ->
                                 module_info_source_file(Module, SourcePrefix);
                             false ->
                                 guess_source_file(AppsDirPaths, Module, ExecRoot)
                         end,
              case SFResult of
                  {ok, SF} ->
                      io:format(S, "SF:~s~n", [SF]),

                      {ok, Lines} = cover:analyse(Module, calls, line),
                      {LH, LF} = lists:foldl(
                                   fun ({{_M, N}, Calls}, {LinesHit, LinesFound}) ->
                                           case Calls of
                                               0 ->
                                                   ok;
                                               _ ->
                                                   io:format(standard_error,
                                                             "~s: ~s:~B calls ~B~n",
                                                             [ScriptName, SF, N, Calls])
                                           end,
                                           io:format(S, "DA:~B,~B~n", [N, Calls]),
                                           {LinesHit + is_hit(Calls), LinesFound + 1}
                                   end, {0, 0}, Lines),
                      io:format(S, "LH:~B~n", [LH]),
                      io:format(S, "LF:~B~n", [LF]),
                      io:format(S, "end_of_record~n", []);
                  _ ->
                      io:format(standard_error,
                                "~s: WARNING: failed to locate source file for module ~p~n",
                                [ScriptName, Module])
              end
      end, Modules),
    file:close(S),
    io:format(standard_error, "~s: done.~n", [ScriptName]).

module_info_source_file(Module, Prefix) ->
    try Module:module_info(compile) of
        Info ->
            case proplists:lookup(source, Info) of
                {source, Src} -> apply_source_prefix(Src, Prefix);
                none -> not_found
            end
    catch
        error:undef -> not_found
    end.

apply_source_prefix(Src, "") ->
    {ok, Src};
apply_source_prefix(Src, Prefix) ->
    case string:str(Src, Prefix) of
        0 -> not_found;
        I -> {ok, lists:nthtail(I - 1, Src)}
    end.

guess_source_file([], _, _) ->
    not_found;
guess_source_file([AppsDir | Rest], Module, SourceRoot) ->
    case source_file(Module, SourceRoot, AppsDir) of
        not_found ->
            guess_source_file(Rest, Module, SourceRoot);
        P ->
            P
    end.

source_file(Module, SourceRoot, AppsDir) ->
    Pattern = filename:join([AppsDir, "*", "src", atom_to_list(Module) ++ ".erl"]),
    case filelib:wildcard(Pattern, SourceRoot) of
        [Path] -> {ok, Path};
        _ -> generated_source_file(Module, SourceRoot, AppsDir)
    end.

generated_source_file(Module, SourceRoot, AppsDir) ->
    Pattern = filename:join(["bazel-out", "*", "bin", AppsDir, "*", "src", atom_to_list(Module) ++ ".erl"]),
    case filelib:wildcard(Pattern, SourceRoot) of
        [Path] ->
            AppName = filename:basename(filename:dirname(filename:dirname(Path))),
            {ok, filename:join(["bazel-bin", AppsDir, AppName, "src", filename:basename(Path)])};
        _ ->
            not_found
    end.

is_hit(0) ->
    0;
is_hit(_) ->
    1.
