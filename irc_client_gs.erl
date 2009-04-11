-module(irc_client_gs).

-compile(export_all).

-import(client, [rpc/2]).	  

-define(S(X), {'#S',X}).
s(X) -> {'#S', X}.

batch([Nick]) ->
    start(atom_to_list(Nick)).

start(Nick) ->
    spawn(fun() -> init1(Nick) end).
	
init1(Nick) ->
    case client:connect("enfield.sics.se", 2000) of
	{ok, Pid, Name} ->
	    {reply, {ok,_},_} = client:rpc(Pid, {startService, s("irc_server"),
						 []}),
	    client:install_handler(Pid, fun print_msg/1),
	    {reply, _, _} = rpc(Pid, logon),
	    Self = self(),
	    client:install_handler(Pid, fun(M) ->
						send_self(M, Self)
					end),
	    case rpc(Pid, {nick, s(Nick)}) of
		{reply, false, _} ->
		    client:stop(Pid),
		    io:format("Nick was in use try again~n"),
		    erlang:halt();
		{reply, true, active} ->
		    init(Pid, Nick)
	    end,
	    io:format("client stops~n");
	{error, socket} ->
	    io:format("Cannot make TCP connection~n"),
	    erlang:halt()
    end.

init(Pid, Nick) ->
    S=gs:start(),
    Width=250,Height=170,
    W= gs:window(S,[{title,"IRC client"},
		 {width,Width},{height,Height},{map,true}]),
    L1 = gs:label(W, [{x,10},{y,10},{label,{text,"Nick:" ++ Nick}}]),
    E1=gs:entry(W, [{x,10},{y,40},{width, 120}]),
    gs:button(W,[{x,130},{y,40},{data, join},{label,{text,"Join Group"}}]),
    gs:config(E1, {text, "erlang"}),
    E2=gs:entry(W, [{x,10},{y,70},{width, 120}]),
    gs:button(W,[{x,130},{y,70}, {data,nick},{label,{text,"Change Nick"}}]),
    gs:button(W,[{x,10},{y,110}, {data,quit}, {label,{text,"Quit"}}]),
    loop(S, dict:new(), Pid, L1, E1,E2).

loop(S, Dict, Pid, L1, E1, E2) ->
    receive
	{gs,_,click,nick,_} ->
	    Nick = gs:read(E2, text),
	    io:format("Change nick to:~s~n",[Nick]), 
	    case rpc(Pid, {nick, s(Nick)}) of
		{reply, false, _} ->
		    gs:config(E2, {text, "** bad nick **"}),
		    loop(S, Dict, Pid, L1, E1, E2);
		{reply, true, active} ->
		    io:format("nick was changed~n"),
		    gs:config(L1, {label, {text, "Nick: " ++ Nick}}),
		    loop(S, Dict, Pid, L1, E1, E2)
	    end,
	    loop(S, Dict, Pid, L1, E1, E2);
	{gs,_,click,{leave,Group},_} ->
	    io:format("I leave: ~s~n",[Group]),
	    case dict:find(Group, Dict) of
		{ok, {W,_}} ->
		    gs:destroy(W),
		    Dict1 = dict:erase(Group, Dict),
		    rpc(Pid, {leave, s(Group)}),
		    loop(S, Dict1, Pid, L1, E1, E2);
		error ->
		    loop(S, Dict, Pid, L1, E1, E2)
	    end;
	{gs,_,click,join,_} ->
	    Group = gs:read(E1, text),
	    io:format("Join:~s~n",[Group]),
	    case Group of
		"" ->
		    loop(S, Dict, Pid, L1, E1, E2);
		_ ->
		    case dict:find(Group, Dict) of
			{ok, W} ->
			    loop(S, Dict, Pid, L1, E1, E2);
			error ->
			    W = new_group(S, Group),
			    rpc(Pid, {join, s(Group)}),
			    loop(S, dict:store(Group, W, Dict), Pid, 
				 L1, E1, E2)
		    end
	    end;
	{gs,_,click,quit,_} ->
	    erlang:halt();
	{gs,Obj,keypress,G,['Return'|_]} ->
	    Str = gs:read(Obj, text),
	    gs:config(Obj, {text, ""}),
	    io:format("Send: ~s to ~s~n",[Str, G]),
	    rpc(Pid, {msg, s(G), s(Str ++ "\n")}), 
	    loop(S, Dict, Pid, L1, E1, E2);
	{gs,Obj,keypress,G,_} ->
	    loop(S, Dict, Pid, L1, E1, E2);
	{event, {leaves, Who, Group}} ->
	    display(Group, Dict, Who  ++ " leaves the group\n"),
	    loop(S, Dict, Pid, L1, E1, E2);
	{event, {joins, Who, Group}} ->
	    display(Group, Dict, Who  ++ " joins the group\n"),
	    loop(S, Dict, Pid, L1, E1, E2);
	{event, {changesName, Old, New, Group}} ->
	    display(Group, Dict, Old ++ " changes name to " ++ New ++ "\n"),
	    loop(S, Dict, Pid, L1, E1, E2);
	{event, {msg, From, Group, Msg}} ->
	    display(Group, Dict, From ++ " > " ++ Msg),
	    loop(S, Dict, Pid, L1, E1, E2);
	X -> 
	    io:format("man: got other: ~w~n",[X]),
	    loop(S, Dict, Pid, L1, E1, E2)
    end.

display(Group, Dict, Str) ->
    case dict:find(Group, Dict) of
	{ok, {W, Txt}} ->
	    gs:config(Txt, {insert, {'end', Str}});
	error ->
	    io:format("Cannot display:~s ~s~n",[Group, Str])
    end.

new_group(S, Name) ->
    Width=450,Height=350,
    W  = gs:window(S,[{title,"Name"},
		    {width,Width},{height,Height},{map,true}]),
    L1 = gs:label(W, [{x,10},{y,10},{label,{text,"Group:" ++ Name}}]),
    T1 = gs:editor(W,  [{x,10},{y,40}, 
			{width,Width-20},
			{height,Height-120},
			{vscroll, right}]), 
    E1 = gs:entry(W, [{x,10},{y,Height-70},{width, Width-20},
		      {data, Name},
		      {keypress,true}]),
    gs:button(W,[{x,10},{y,Height-35},
		 {data, {leave, Name}},{label,{text,"Leave Group"}}]),
    {W, T1}.

send_self(Msg, Pid) ->    
    Pid ! {event, ubf:deabstract(Msg)},
    fun(I) -> send_self(I, Pid) end.
	    

print_msg(X) ->
    case ubf:deabstract(X) of
	{joins, Who, Group} ->
	    io:format("~s joins the group ~s~n",[Who, Group]);
	{leaves, Who, Group} ->
	    io:format("~s leaves the group ~s~n",[Who, Group]);
	{msg, Who, Group, Msg} ->
	    io:format("Msg from ~s to ~s => ~s~n",[Who, Group,Msg]);
	{changesName, Old, New, Group} ->
	    io:format("~s is now called ~s in group ~s~n",
		      [Old, New, Group]);
	Other ->
	    io:format("==> ~p~n",[Other])
    end,
    fun print_msg/1.



