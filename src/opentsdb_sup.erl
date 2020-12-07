%%%-------------------------------------------------------------------
%%% @author Administrator
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. 12月 2020 14:38
%%%-------------------------------------------------------------------
-module(opentsdb_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).


start_link() ->
  supervisor:start_link({local, opentsdb_sup}, opentsdb_sup,[]).

init([]) -> {ok, {{one_for_one, 10, 100}, []}}.
