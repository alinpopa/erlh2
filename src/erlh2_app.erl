-module(erlh2_app).

-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _StartArgs) ->
    erlh2_sup:start_link().

stop(_State) -> ok.

