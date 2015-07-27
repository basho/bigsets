%% -------------------------------------------------------------------
%%
%% A dot indexed orswot. @TODO Use references to elements to lessen storage
%%
%% Copyright (c) 2007-2015 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(bigset_delta_orswot).

%% API
-export([new/0, value/1]).
-export([update/3, merge/2]).

-compile(export_all).

-define(DICT, dict).

new() ->
    {bigset_clock:fresh(), ?DICT:new()}.

value({_Clock, Entries}) ->
    lists:sort([K || {K, _Dots} <- ?DICT:to_list(Entries)]).

update({Elem, Actor, Cnt, <<1:1>>), Set) ->
    %% A remove

update({Elem, Actor, Cnt, <<0:1>>}, Set) ->
    %% An add

merge({LHClock, LHEntries, LHSeen}=LHS, {RHClock, RHEntries, RHSeen}=RHS) ->
    Clock0 = riak_dt_vclock:merge([LHClock, RHClock]),

    LHKeys = sets:from_list(orddict:fetch_keys(LHEntries)),
    RHKeys = sets:from_list(orddict:fetch_keys(RHEntries)),
    CommonKeys = sets:intersection(LHKeys, RHKeys),
    LHUnique = sets:subtract(LHKeys, CommonKeys),
    RHUnique = sets:subtract(RHKeys, CommonKeys),
    Entries00 = merge_common_keys(CommonKeys, LHS, RHS),

    Entries0 = merge_disjoint_keys(LHUnique, LHEntries, RHClock, RHSeen, Entries00),
    Entries = merge_disjoint_keys(RHUnique, RHEntries, LHClock, LHSeen, Entries0),

    Seen0 = lists:umerge(LHSeen, RHSeen),
    {Clock, Seen} = compress_seen(Clock0, Seen0),
    {Clock, Entries, Seen}.

compress_seen(Clock, Seen) ->
    lists:foldl(fun(Node, {ClockAcc, SeenAcc}) ->
                        Cnt = riak_dt_vclock:get_counter(Node, Clock),
                        Cnts = proplists:lookup_all(Node, Seen),
                        case compress(Cnt, Cnts) of
                            {Cnt, Cnts} ->
                                {ClockAcc, lists:umerge(Cnts, SeenAcc)};
                            {Cnt2, []} ->
                                {riak_dt_vclock:merge([[{Node, Cnt2}], ClockAcc]),
                                 SeenAcc};
                            {Cnt2, Cnts2} ->
                                {riak_dt_vclock:merge([[{Node, Cnt2}], ClockAcc]),
                                 lists:umerge(SeenAcc, Cnts2)}
                        end
                end,
                {Clock, []},
                proplists:get_keys(Seen)).

compress(Cnt, []) ->
    {Cnt, []};
compress(Cnt, [{_A, Cntr} | Rest]) when Cnt >= Cntr ->
    compress(Cnt, Rest);
compress(Cnt, [{_A, Cntr} | Rest]) when Cntr - Cnt == 1 ->
    compress(Cnt+1, Rest);
compress(Cnt, Cnts) ->
    {Cnt, Cnts}.

%% @doc check if each element in `Entries' should be in the merged
%% set.
merge_disjoint_keys(Keys, Entries, SetClock, SetSeen, Accumulator) ->
    sets:fold(fun(Key, Acc) ->
                      Dots = orddict:fetch(Key, Entries),
                      case riak_dt_vclock:descends(SetClock, Dots) of
                          false ->
                              %% Optimise the set of stored dots to
                              %% include only those unseen
                              NewDots = riak_dt_vclock:subtract_dots(Dots, SetClock),
                              case lists:subtract(NewDots, SetSeen) of
                                  [] ->
                                      Acc;
                                  NewDots2 ->
                                      orddict:store(Key, lists:usort(NewDots2), Acc)
                              end;
                          true ->
                              Acc
                      end
              end,
              Accumulator,
              Keys).

%% @doc merges the minimal clocks for the common entries in both sets.
merge_common_keys(CommonKeys, {LHSClock, LHSEntries, LHSeen}, {RHSClock, RHSEntries, RHSeen}) ->

    %% If both sides have the same values, some dots may still need to
    %% be shed.  If LHS has dots for 'X' that RHS does _not_ have, and
    %% RHS's clock dominates those dots, then we need to drop those
    %% dots.  We only keep dots BOTH side agree on, or dots that are
    %% not dominated. Keep only common dots, and dots that are not
    %% dominated by the other sides clock

    sets:fold(fun(Key, Acc) ->
                      V1 = orddict:fetch(Key, LHSEntries),
                      V2 = orddict:fetch(Key, RHSEntries),

                      CommonDots = sets:intersection(sets:from_list(V1), sets:from_list(V2)),
                      LHSUnique = sets:to_list(sets:subtract(sets:from_list(V1), CommonDots)),
                      RHSUnique = sets:to_list(sets:subtract(sets:from_list(V2), CommonDots)),
                      LHSKeep = lists:subtract(riak_dt_vclock:subtract_dots(LHSUnique, RHSClock), RHSeen),
                      RHSKeep = lists:subtract(riak_dt_vclock:subtract_dots(RHSUnique, LHSClock), LHSeen),
                      V = riak_dt_vclock:merge([sets:to_list(CommonDots), LHSKeep, RHSKeep]),
                      %% Perfectly possible that an item in both sets should be dropped
                      case V of
                          [] ->
                              orddict:erase(Key, Acc);
                          _ ->
                              orddict:store(Key, lists:usort(V), Acc)
                      end
              end,
              orddict:new(),
              CommonKeys).
