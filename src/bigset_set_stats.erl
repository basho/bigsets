% -------------------------------------------------------------------
%%
%% set_stats: Use local-client on bigsets attach session to grab some details
%%            about set lengths for benchmarking
%%
%% Copyright (c) 2016 Basho Techonologies
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
-module(bigset_set_stats).

-compile(export_all).

-define(KEY, <<"bench_set">>).

calc() ->
    calc(?KEY).
calc(Key) ->
    C = start_local_client(),
    SetInfo = get_key_set_avg_binary_and_size(C, Key),
    LengthAvg = set_avg(SetInfo, length),
    BinSizeAvg = set_avg(SetInfo, bin_size),
    StdBinAvg  = set_avg(SetInfo, bin_std),
    io:format("Number of sets: ~p\n" ++
              "Average crdt set size: ~p\n" ++
              "Average binary size: ~p\n" ++
              "Standard Deviation of crdt sets sizes: ~p\n" ++
              "Avg Standard Deviation of bin size within each set: ~p\n" ++
              "\n~p\n",
              [length(SetInfo),
               LengthAvg,
               BinSizeAvg,
               set_std(SetInfo, LengthAvg, length),
               StdBinAvg,
               SetInfo]).

set_std(L, Avg, length) ->
    F = fun({_, _, _, SetLength}, Acc) ->
                Acc + (SetLength - Avg) * (SetLength - Avg)
        end,
    set_std(F, L);
set_std(L, Avg, bin_size) ->
    F = fun({_, BinAvg, _, _}, Acc) ->
                Acc + (BinAvg - Avg) * (BinAvg - Avg)
        end,
    set_std(F, L).
set_std(F, L) ->
    case length(L) == 1 of
        true ->
            0.0;
        false ->
            Variance = lists:foldl(F, 0.0, L) / (length(L) - 1),
            math:sqrt(Variance)
    end.

set_avg(L, length) ->
    F = fun({_, _, _, SetLength}, Acc) -> Acc + SetLength end,
    set_avg(F, L);
set_avg(L, bin_size) ->
    F = fun({_, BinAvg, _, _}, Acc) -> Acc + BinAvg end,
    set_avg(F, L);
set_avg(L, bin_std) ->
    F = fun({_, _, BinStd, _}, Acc) -> Acc + BinStd end,
    set_avg(F, L);
set_avg(F, L) ->
    Sum = lists:foldl(F, 0, L),
    Sum / length(L).

set_bin_size_avg(SetOfVals) ->
    F = fun(Elem, Acc) -> Acc + size(Elem) end,
    Sum = lists:foldl(F, 0, SetOfVals),
    Sum / length(SetOfVals).

set_bin_size_std(SetOfVals) ->
    Len = length(SetOfVals),
    case Len == 1 of
        true -> 0.0;
        false ->
            Avg = set_bin_size_avg(SetOfVals),
            F = fun(Elem, Acc) ->
                        Acc + (size(Elem) - Avg) * (size(Elem) - Avg)
                end,
            Variance = lists:foldl(F, 0.0, SetOfVals) / (length(SetOfVals) - 1),
            math:sqrt(Variance)
    end.

start_local_client() ->
    bigset_client:new().

get_key_set_avg_binary_and_size(C, Key) ->
    {ok, {ctx, _Ctx}, {elems, Set}} = bigset_client:read(Key, [], C),
    [{Key,
       set_bin_size_avg(Set),
       set_bin_size_std(Set),
       length(Set)}].
