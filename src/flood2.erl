-module(flood2).
-author('roberto@widetag.com').
-compile(export_all).


% starts pong
start_pong() ->
	register(flood_pong, spawn(fun() -> pong_loop() end)).

pong_loop() ->
	receive
		{{Sender, SenderNode}, Any} ->
			% pong back
			qr:route({Sender, SenderNode}, {pong, Any}),
			pong_loop();
		shutdown ->
			io:format("pong shutdown~n",[]);
		_Ignore ->
			pong_loop()
	after 30000 ->
		io:format("pong timeout, shutdown~n",[])
	end.


% start ping
start_ping(PongNode, Num) ->
	register(flood_ping, spawn(fun() -> ping_loop(Num, now(), Num) end)),
	send(PongNode, Num).

send(_PongNode, 0) ->
	ok;
send(PongNode, Num) ->
	% send a spawned ping
	spawn(fun() -> qr:route({flood_pong, PongNode}, {{flood_ping, node()}, ping_request}) end),
	send(PongNode, Num - 1).

ping_loop(Num, Start, 0) ->
	T = timer:now_diff(now(), Start),
	io:format("RECEIVED ALL ~p in ~p ms [~p/min]~n",[Num, T, (Num*60000000/T)]);
ping_loop(Num, Start, Count) ->
	receive 
		{pong, _PingBack} ->
			ping_loop(Num, Start, Count-1);
		_Received ->
			ping_loop(Num, Start, Count)
	after 10000 ->
		io:format("ping timeout, missing ~p pong, shutdown~n",[Count])
	end.

