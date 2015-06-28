-module(erlh2_tcp_manager).
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).
-export([start_link/2, detach/0]).

-define(SERVER, ?MODULE).

-record(server_state, {socket, listeners_size}).
-define(TCP_OPTIONS, [binary, {packet, 0}, {active, false}, {reuseaddr, true}]).
-define(LISTENER, erlh2_tcp_listener).

start_link(Port, ListenersSize) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Port, ListenersSize], []).

detach() ->
    gen_server:call(?MODULE, detach).

init([Port, ListenersSize]) ->
    case gen_tcp:listen(Port, ?TCP_OPTIONS) of
        {ok, Socket} ->
            ok = spawn_listeners(Socket, ListenersSize),
            error_logger:info_msg("TCP Server started on port ~p, listeners size ~p~n", [Port, ListenersSize]),
            {ok, #server_state{socket = Socket, listeners_size = ListenersSize}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(detach, {From, _Ref}, State = #server_state{socket = Socket}) ->
    ok = spawn_listeners(Socket, 1),
    unlink(From),
    {reply, ok, State};
handle_call(stop, _From, State) ->
    {stop, normal, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #server_state{socket = Socket}) ->
    gen_tcp:close(Socket).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% @private
spawn_listeners(_, 0) ->
    ok;
spawn_listeners(Socket, Size) ->
    ?LISTENER:start_link(Socket),
    spawn_listeners(Socket, Size - 1).

