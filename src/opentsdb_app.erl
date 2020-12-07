%%%-------------------------------------------------------------------
%%% @author Administrator
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. 12月 2020 14:37
%%%-------------------------------------------------------------------
-module(opentsdb_app).

-behaviour(application).

-export([start/2]).

-export([stop/1]).

start(_Type, _Args) -> opentsdb_sup:start_link().

stop(_State) -> ok.