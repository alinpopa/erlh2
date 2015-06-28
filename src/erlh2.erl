-module(erlh2).
-export([
    start/0
]).

-spec start() -> ok.
start() ->
    lists:foreach(fun application:start/1,
                  [Dep || Dep <- resolve_deps(erlh2),
                          not is_otp_base_app(Dep)]),
    ok.

-spec dep_apps(atom()) -> list(atom()).
dep_apps(App) ->
    application:load(App),
    {ok, Apps} = application:get_key(App, applications),
    Apps.

-spec all_deps(atom(), list(atom())) -> list(atom()).
all_deps(App, Deps) ->
    [[all_deps(Dep, [App|Deps]) || Dep <- dep_apps(App),
                                   not lists:member(Dep, Deps)], App].

-spec resolve_deps(atom()) -> list(atom()).
resolve_deps(App) ->
    DepList = all_deps(App, []),
    {AppOrder, _} = lists:foldl(fun(E, {List, Set}) ->
                                        case sets:is_element(E, Set) of
                                            true ->
                                                {List, Set};
                                            false ->
                                                {List ++ [E], sets:add_element(E, Set)}
                                        end
                                end,
                                {[], sets:new()},
                                lists:flatten(DepList)),
    AppOrder.

-spec is_otp_base_app(atom()) -> boolean().
is_otp_base_app(kernel) ->
    true;
is_otp_base_app(stdlib) ->
    true;
is_otp_base_app(_) ->
    false.

