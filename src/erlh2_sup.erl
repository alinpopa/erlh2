-module(erlh2_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Tcp =
        {erlh2_tcp_sup, {erlh2_tcp_sup, start_link, []},
        permanent, 5000, supervisor, [erlh2_tcp_sup]},
    Processes = [Tcp],
    {ok, {{one_for_one, 10, 10}, Processes}}.

