-module(null_peer).
-behaviour(gen_server).

-include("protocol.hrl").
-include("commands.hrl").

%% API
-export([ start_link/0
        , recv_incoming_packet/5
        ]).

%% gen_server callbacks
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-record(state,
        { host
        }).


%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link(?MODULE, [self()], []).

recv_incoming_packet(Peer, SentTime, Packet, IP, Port) ->
    gen_server:cast(Peer, {incoming_packet, SentTime, Packet, IP, Port}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Host]) ->
    {ok, #state{ host = Host }}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({incoming_packet, SentTime, Packet, IP, Port}, S) ->
    %%
    %% Received an incoming packet of commands.
    %%
    %% - Split and decode the commands from the binary
    %% - Send the commands as individual events to ourselves
    %%
    {ok, Commands} = wire_protocol_decode:commands(Packet),
    lists:foreach(
      fun (C) ->
              gen_server:cast(self(), {incoming_command, SentTime, C, IP, Port})
      end,
      Commands),
    {noreply, S};

handle_cast({incoming_command, SentTime, {H, C = #connect{}}, IP, Port}, S) ->
    %%
    %% Received a Connect command.
    %%
    %% - Verify that the data is sane (TODO)
    %% - Acknowledge the command
    %% - Start a new peer controller and pass in the data from the command
    %%
    {AckH, AckC} = protocol:make_acknowledge_command(H, SentTime),
    HBin = wire_protocol_encode:command_header(AckH),
    CBin = wire_protocol_encode:command(AckC),
    {sent_time, _AckSentTime} =
        host_controller:send_outgoing_commands(
          S#state.host, [HBin, CBin], IP, Port, C#connect.outgoing_peer_id),
    peer_controller:remote_connect(S#state.host, C, IP, Port),
    {noreply, S};

handle_cast(_Msg, State) ->
    {noreply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
