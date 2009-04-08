% ==========================================================================================================
% Queue Router [QR]
% 
% This code is Copyright (C) 2009, Roberto Ostinelli.
% Autor: Roberto Ostinelli <roberto AT ostinelli DOT net>
% ==========================================================================================================
-module(qr).
-behaviour(gen_server).
-author('roberto@widetag.com').
-vsn('0.1').

% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% API
-export([start_link/0, stop/0, route/2]).

% macros
-define(SERVER, ?MODULE).
-define(QR, qr).
-define(QUEUELENGTH, 10).
-define(QUEUETIMEOUT, 200000).	% in MICRO seconds, 200000 = 0.2 sec.


% ============================ \/ API ======================================================================

% Function: {ok,Pid} | ignore | {error, Error}
% Description: Starts the server.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

% Function: -> ok
% Description: Manually stops the server.
stop() ->
	gen_server:cast(?SERVER, stop).
	
% Function() -> void()
% Description: Gets a routing request
route({ToPid, ToNode}, Message) ->
	case ToNode =:= node() of
		true ->
			% send directly
			ToPid ! Message;
		false ->
			% queue
			gen_server:cast(?SERVER, {{queue, ToNode}, {ToPid, Message}})
	end.

% ============================ /\ API ======================================================================


% ============================ \/ GEN_SERVER CALLBACKS =====================================================

% ----------------------------------------------------------------------------------------------------------
% Function: -> {ok, State} | {ok, State, Timeout} | ignore | {stop, Reason}
% Description: Initiates the server.
% ----------------------------------------------------------------------------------------------------------
init([]) ->
	process_flag(trap_exit, true),
    {ok, []}.

% ----------------------------------------------------------------------------------------------------------
% Function: handle_call(Request, From, State) -> {reply, Reply, State} | {reply, Reply, State, Timeout} |
%                                      {noreply, State} | {noreply, State, Timeout} |
%                                      {stop, Reason, Reply, State} | {stop, Reason, State}
% Description: Handling call messages.
% ----------------------------------------------------------------------------------------------------------

% handle_call generic fallback
handle_call(_Request, _From, _State) ->
    {reply, undefined, ?QUEUETIMEOUT div 1000}.

% ----------------------------------------------------------------------------------------------------------
% Function: handle_cast(Msg, State) -> {noreply, State} | {noreply, State, Timeout} | {stop, Reason, State}
% Description: Handling cast messages.
% ----------------------------------------------------------------------------------------------------------

% add incoming routing request to queue
handle_cast({{queue, DestNode}, {ToPid, Message}}, Queue) ->
	% to pid
	Msg = {route, ToPid, Message},
	% get if node exists in queue
	case lists:keysearch(DestNode, 1, Queue) of
		false ->
			% add node
			NewQueue = [{DestNode, {now(), [Msg]}}|Queue];
		{value, {DestNode, {CreationTime, MsgList}}} ->
			% check if queue is long enough
			case length(MsgList) >= ?QUEUELENGTH of
				true ->
					% queue of a node is of maximum lenght, send routing message
					{?QR, DestNode} ! {queue_route, [Msg|MsgList]},
					% empty queue for node
					NewQueue = lists:keydelete(DestNode, 1, Queue);
				false ->
					% add message to queue list and replace node
					NewQueue = lists:keyreplace(DestNode, 1, Queue, {DestNode, {CreationTime, [Msg|MsgList]}})
			end
	end,
	% purge timeout
	PurgedQueue = purge_queue_selective(NewQueue),
	{noreply, PurgedQueue, ?QUEUETIMEOUT div 1000};

% manual shutdown
handle_cast(stop, State) ->
	{stop, normal, State};

% handle_cast generic fallback (ignore)
handle_cast(_Msg, State) ->
	% io:format("received cast message: ~p~n", [_Msg]),
    {noreply, State, ?QUEUETIMEOUT div 1000}.

% ----------------------------------------------------------------------------------------------------------
% Function: handle_info(Info, State) -> {noreply, State} | {noreply, State, Timeout} | {stop, Reason, State}
% Description: Handling all non call/cast messages.
% ----------------------------------------------------------------------------------------------------------

% timeout on a cast message, purge queue
handle_info(timeout, Queue) ->
	% purge timeout
	PurgedQueue = purge_queue(Queue),
	% return
	{noreply, PurgedQueue};
	
handle_info({queue_route, MsgList}, State) ->
	RouteFun = fun({route, ToPid, Message}) ->
		% local send to node
		ToPid ! Message
	end,
	lists:foreach(RouteFun, MsgList),
	% return
	{noreply, State, ?QUEUETIMEOUT div 1000};
	
% handle_info generic fallback (ignore)
handle_info(_Info, State) ->
    {noreply, State, ?QUEUETIMEOUT div 1000}.


% ----------------------------------------------------------------------------------------------------------
% Function: terminate(Reason, State) -> void()
% Description: This function is called by a gen_server when it is about to terminate. When it returns,
% the gen_server terminates with Reason. The return value is ignored.
% ----------------------------------------------------------------------------------------------------------
terminate(_Reason, Queue) ->
	% purge remaining queue
	% io:format("BEFORE CLOSING: ~p~n",[Queue]),
	purge_queue(Queue),
    terminated.

% ----------------------------------------------------------------------------------------------------------
% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
% Description: Convert process state when code is changed.
% ----------------------------------------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

% ============================ /\ GEN_SERVER CALLBACKS =====================================================


% ============================ \/ INTERNAL FUNCTIONS =======================================================

% Function -> PurgedQueue
% Description: Loop queue and purge only nodes on timeout.
purge_queue_selective(Queue) ->
	% check timeout, send and remove element if needed
	FilterFun = fun({DestNode, {CreationTime, MsgList}}) ->
		case timer:now_diff(now(), CreationTime) > ?QUEUETIMEOUT of
			true ->
				% timeout for a node, send routing message
				{?QR, DestNode} ! {queue_route, MsgList},
				% delete node from queue
				false;
			false ->
				true
		end
	end,
	% return cleaned queue
	lists:filter(FilterFun, Queue).

% Function -> PurgedQueue
% Description: Loop queue and purge all nodes.
purge_queue(Queue) ->
	% sent to all remaining
	FilterFun = fun({DestNode, {_CreationTime, MsgList}}) ->
		% send routing message
		{?QR, DestNode} ! {queue_route, MsgList}
	end,
	lists:foreach(FilterFun, Queue),
	% return an empty queue
	[].

% ============================ /\ INTERNAL FUNCTIONS =======================================================
