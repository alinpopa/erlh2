-module(erlh2_tcp_listener).
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).
-export([start_link/1, send_to_client/2]).

-define(SERVER, ?MODULE).
-define(LISTENER_MANAGER, erlh2_tcp_manager).
-define(FRAME_HEADER_SIZE, 9).
-define(REMOTE_STREAM_WINDOW_SIZE, 65535).
-define(REMOTE_SESSION_WINDOW_SIZE, 65535).
-define(LOCAL_SESSION_WINDOW_SIZE, 65535).
-define(LOCAL_STREAM_WINDOW_SIZE, 65535).
-define(GOAWAY, 16#7).
-define(FLAG_NONE, 0). %% Defined for clarity
-define(PROTOCOL_ERROR, 16#1).

-record(httpstate, {socket, %% socket of this connection
                transport,
                writer,
                writermon,
                framer=expect_preface, %% framer state
                %hpackenc=hpack:new_encoder(), %% hpack encoder
                %hpackdec=hpack:new_decoder(), %% hpack decoder
                initial_window_size=?REMOTE_STREAM_WINDOW_SIZE,
                %% true if remote peer enables push
                remote_enable_push=true,
                %% remove connection window size
                remotewin=?REMOTE_SESSION_WINDOW_SIZE,
                localwin=?LOCAL_SESSION_WINDOW_SIZE,
                outq=queue:new(),
                last_recv_stream_id=0,
                last_sent_stream_id=0,
                streams=[], %% orddict(), mapping stream ID to stream.
                pids=[], %% orddict(), mapping pid to stream ID.
                headersbuf,
                bin = <<>> %% buffer to store pending received data
               }).
-record(state, {listening_socket, client_socket}).

start_link(Socket) ->
    gen_server:start_link(?MODULE, [Socket], []).

send_to_client(Pid, Msg) ->
    EndOfMsg = <<"\r\n">>,
    gen_server:cast(Pid, {send_to_client, <<Msg/binary, EndOfMsg/binary>>}).

init([Socket]) ->
    gen_server:cast(self(), {listen}),
    {ok, #state{listening_socket = Socket}}.

handle_cast({listen}, State) ->
    {ok, ClientSocket} = gen_tcp:accept(State#state.listening_socket),
    error_logger:info_msg("Client connected (concurrent no. of processes ~p)~n", [length(processes())]),
    gen_tcp:controlling_process(ClientSocket, self()),
    inet:setopts(ClientSocket, [{active, once}]),
    ?LISTENER_MANAGER:detach(),
    {noreply, State#state{client_socket = ClientSocket}};
handle_cast({send_to_client, Msg},State) ->
    gen_tcp:send(State#state.client_socket, [Msg]),
    {noreply,State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_info({tcp, ClientSocket, BinMsg}, State) ->
    io:format("TCP: ~p~n",[BinMsg]),
    on_recv(BinMsg, #httpstate{}),
    %% parse BinCmd
    ClientMsg = <<"ana are mere">>,
    gen_tcp:send(ClientSocket, [ClientMsg]),
    inet:setopts(State#state.client_socket, [{active, once}]),
    {noreply, State};
handle_info({tcp_closed, _ClientSocket}, State) ->
    error_logger:info_msg("Connection closed by client (concurrent no. of processes ~p)~n", [length(processes())]),
    {stop, normal, State};
handle_info(Info, State) ->
    error_logger:warning_msg("UNKNOWN info ~p~n", [Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

on_recv(<<"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n", Rest/binary>>,
        State=#httpstate{framer=expect_preface}) ->
    on_recv(Rest, State#httpstate{framer=read_frame, bin = <<>>});
on_recv(Bin, State=#httpstate{framer=expect_preface}) when size(Bin) < 24 ->
    State#httpstate{bin=Bin};
on_recv(_Bin, State=#httpstate{framer=expect_preface}) ->
    error_logger:info_msg("Terminate now~n"),
    terminate_now(State);
on_recv(<<Len:24, _Rest/binary>>, State) when Len > 16384 ->
    error_logger:info_msg("Connection error~n"),
    connection_error(State, ?PROTOCOL_ERROR);
on_recv(Bin = <<Len:24, _Type:8, _Flag:8, _:1, _StreamId:31, Rest/binary>>,
        State=#httpstate{socket=Socket, transport=Transport})
  when Len > size(Rest) ->
    ok = transport_setopts(Transport, Socket, [{active, once}]),
    State#httpstate{bin=Bin};
on_recv(<<Len:24, Type:8, Flag:8, _:1, StreamId:31, Rest/binary>>, State) ->
    io:format("Frame Len=~p Type=~p Flag=~2.16.0B StreamId=~p~n",
              [Len, Type, Flag, StreamId]),
    handle_frame(Rest, Len, Type, Flag, StreamId, State);
on_recv(Bin, State=#httpstate{socket=Socket, transport=Transport})
  when size(Bin) < ?FRAME_HEADER_SIZE ->
    %% Sometimes we will call transport_setopts when underlying Socket
    %% was closed.
    case transport_setopts(Transport, Socket, [{active, once}]) of
        {error, _Reason} ->
            stop;
        ok ->
            State#httpstate{bin=Bin}
    end.

transport_setopts(tcp, Socket, Opts) ->
    inet:setopts(Socket, Opts).

handle_frame(_Rest, _Len, _Type, _Flag, _StreamId, State) ->
    io:format("Handle frame ~p~n", [State]),
    ok.

terminate_now(_State) ->
    stop.

connection_error(State, ErrorCode) ->
    send_goaway(State, ErrorCode),
    terminate_now(State).

send_goaway(State=#httpstate{last_recv_stream_id=LastRecvStreamId}, ErrorCode) ->
    Bin = <<8:24, ?GOAWAY:8, ?FLAG_NONE:8, 0:32, 0:1, LastRecvStreamId:31,
            ErrorCode:32>>,
    %% Sending GOAWAY is synchronous, since we are always send GOAWAY
    %% just before terminating connection.
    ok = send_sync(Bin, State),
    ok.

send_sync(Bin, #httpstate{writer=Pid}) ->
    ok = gen_server:call(Pid, {blob, Bin}),
    ok.

