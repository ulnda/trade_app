-module(trade_fsm).
-compile(export_all).

-behaviour(gen_fsm).

-record(state, { name = "",
								 other,
								 ownitems = [],
								 otheritems = [],
								 monitor,
								 from }).

%%% PUBLIC API

start(Name) ->
	gen_fsm:start(?MODULE, [Name], []).

start_link(Name)
	gen_fsm:start_link(?MODULE, [Name], []).

%% Ask for a begin session. Returns when/if the other accepts
trade(OwnPid, OtherPid) ->
	gen_fsm:sync_send_event(OwnPid, { negotiate, OtherPid }, 300000).

%% Accept someone's trade offer
accept_trade(OwnPid) ->
	gen_fsm:sync_send_event(OwnPid, accept_negotiate).

%% Send an item on the table to be traded
make_offer(OwnPid, Item) ->
	gen_fsm:send_event(OwnPid, { make_offer, Item }).

%% Cancel trade offer
retract_offer(OwnPid, Item) ->
	gen_fsm:send_event(OwnPid, { retract_offer, Item }).

%% Mention that you're reade for a trade. When the other 
%% player also declares being ready, the trade is done
ready(OwnPid) ->
	gen_fsm:sync_send_event(OwnPid, ready, infinity).

%% Cancel the transaction
cancel(OwnPid) ->
	gen_fsm:sync_send_all_state_event(OwnPid, cancel).


%%% CLIENT-TO-CLIENT API
%% These calls are only listed for the gen_fsm to call
%% among themselves
%% All calls are asynchronous to avoid deadlocks

%% Ask the other FSM for a trade session
ask_negotiate(OtherPid, OwnPid) ->
	gen_fsm:send_event(OtherPid, { ask_negotiate, OwnPid }).

%% Forward the client message accepting the transaction
accept_negotiate(OtherPid, OwnPid) ->
	gen_fsm:send_event(OtherPid, { accept_negotiate, OwnPid }).

%% Forward a client's offer
do_offer(OtherPid, Item) ->
	gen_fsm:send_event(OtherPid, { do_offer, Item }).

%% Forward a client's offer cancellation
undo_offer(OtherPid, Item) ->
	gen_fsm:send_event(OtherPid, { undo_offer, Item }).

%% Ask the other side if he's ready to trade
are_you_ready(OtherPid) ->
	gen_fsm:send_event(OtherPid, are_you_ready).

%% Reply that the side is not ready to trade
%% i.e. is not in 'wait' state

not_yet(OtherPid) ->
	gen_fsm:send_event(OtherPid, not_yet).

%% Tells the other fsm that the user is currently waiting
%% for the ready state. State shpuld transition to 'ready'
am_ready(OtherPid) ->
	gen_fsm:send_event(OtherPid, 'ready!').

%% Acknowledge that the fsm is in ready state
ack_trans(OtherPid) ->
	gen_fsm:send_event(OtherPid, ack).

%% Ask if ready to commit
ask_commit(OtherPid) ->
	gen_fsm:sync_send_event(OtherPid, ask_commit).

%% Begin the synchronous commit
do_commit(OtherPid) ->
	gen_fsm:sync_send_event(OtherPid, do_commit).

%% Make the other FSM aware that your client cancelled the trade
notify_cancel(OtherPid) ->
	gen_fsm:send_all_state_event(OtherPid, cancel).

%%% GEN_FSM API
init(Name) ->
	{ ok, idle, #state{ name = Name } }.

%% Idle state is the state before any trade is done.
%% The other player asks for a negotiation. We basically
%% only wait for our own user to accept the trade,
%% and store the other's Pid for future uses

idle({ ask_negotiate, OtherPid }, S = #state{}) ->
	Ref = monitor(process, OtherPid),
	notice(S, "~p asked for a trade negotiation", [OtherPid]),
	{ next_state, idle_wait, S#state{ other = OtherPid, monitor = Ref } };

idle(Event, Data) ->
	unexpected(Event, idle),
	{ next_state, idle, Data }.

%% Trade call coming from the user. Forward to the other side,
%% forward it and store the other's Pid
idle({ negotiate, OtherPid }, From, S = #state{}) ->
	ask_negotiate(OtherPid, self()),
	notice(S, "asking user ~p for a trade", [OtherPid]),
	Ref = monitor(process, OtherPid),
	{ next_state, idle_wait, S#state{ other = OtherPid, monitor = Ref, from = From } };

idle(Event, _From, Data) ->
	unexpected(Event, idle),
	{ next_state, idle, Data }.

%% The other side asked for a negotiation while we asked for it too.
%% this means both definitely agree to the idea of doing a trade.
%% Both sides can assume the other feels the same!
idle_wait({ ask_negotiate, OtherPid }, S = #state{ other = OtherPid }) ->
	gen_fsm:reply(S#state.from, ok),
	notice(S, "starting negotiation", []),
	{ next_state, negotiate, S };

%% The other side has accepted our offer. Move to negotiate state
idle_wait({ accept_negotiate, OtherPid }, S = #state{ other = OtherPid }) ->
	gen_fsm:reply(S#state.from, ok),
	notice(S, "starting negotiation", []),
	{ next_state, negotiate, S };

%% Different call from someone else. Not supported! Let it die
idle_wait(Event, Data) ->
	unexpected(Event, idle_wait),
	{ next_state, idle_wait, Data }.