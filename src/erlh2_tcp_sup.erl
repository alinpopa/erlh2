-module(erlh2_tcp_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, App} = application:get_application(?MODULE),
    {ok, TcpPort} = application:get_env(App, tcp_port),
    TcpManager =
        {erlh2_tcp_manager, {erlh2_tcp_manager, start_link, [TcpPort, 10]},
        permanent, 5000, worker, [erlh2_tcp_manager]},
    Processes = [TcpManager],
    {ok, {{one_for_one, 10, 10}, Processes}}.

