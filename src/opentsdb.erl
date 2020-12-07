%%%-------------------------------------------------------------------
%%% @author Administrator
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. 12月 2020 14:40
%%%-------------------------------------------------------------------
-module(opentsdb).

-behaviour(gen_server).

-export([start_link/0, start_link/1, stop/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([put/2, put/3, version/1, version/2]).

-export([unix_timestamp/0, unix_timestamp/1]).

-type server() :: string().

-type present() :: {present, boolean()}.

-type milliseconds() :: integer().

-type metric() :: binary() | atom().

-type timestamp() :: integer().

-type value() :: integer() | float() | binary().

-type tags() :: map().

-record(state,
{server = "localhost:4242" :: server(),
  summary = {present, true} :: present(),
  details = {present, false} :: present(),
  sync = {present, false} :: present(),
  sync_timeout = 0 :: milliseconds(),
  max_batch_size = 20 :: integer()}).

-spec start_link() -> {ok, pid()}.

-vsn("4.2.1").

start_link() -> start_link([]).

start_link(Opts) ->
  gen_server:start_link(opentsdb, [Opts], []).

stop(Pid) -> gen_server:stop(Pid).

-spec put(Pid, DataPoints) -> {ok, integer(), map()} |{erro, atom()} |{error, integer(), map()} when Pid :: pid(),
  DataPoints :: [DataPoint] |DataPoint,
  DataPoint :: #{metric := metric(), timestamp => timestamp(), value := value(), tags := tags()}.

put(Pid, DataPoints) -> put(Pid, DataPoints, []).

-spec put(Pid, DataPoints, Options) -> {ok, integer(), map()} |{erro, atom()} |{error, integer(), map()} when Pid :: pid(),
  DataPoints :: [DataPoint] |DataPoint,
  DataPoint :: #{metric := metric(), timestamp => timestamp(), value := value(), tags := tags()},
  Options :: [Option], Option :: {server, server()} |
  {summary, present()} |{details, present()} |{sync, present()} |{sync_timeout, milliseconds()} |{max_batch_size, integer()}.

put(Pid, DataPoint, Options) when is_map(DataPoint) ->
  put(Pid, [DataPoint], Options);
put(Pid, DataPoints, Options) when is_list(DataPoints) ->
  try preprocess([atom_key_map(Point) || Point <- DataPoints]) of
    DataPoints1 ->
      gen_server:call(Pid, {put, DataPoints1, Options})
  catch
    error:Reason -> {error, Reason}
  end.

version(Pid) -> version(Pid, []).

version(Pid, Options) ->
  gen_server:call(Pid, {version, Options}).

unix_timestamp() -> unix_timestamp(milliseconds).

unix_timestamp(seconds) ->
  {MegaSecs, Secs, _MicroSecs} = erlang:timestamp(),
  MegaSecs * 1000000 + Secs;
unix_timestamp(milliseconds) ->
  {MegaSecs, Secs, MicroSecs} = erlang:timestamp(),
  MegaSecs * 1000000000 + Secs * 1000 + MicroSecs div 1000.

init([Opts]) ->
  State = #state{server =
  proplists:get_value(server, Opts, "localhost:4242"),
    summary =
    {present, proplists:get_value(summary, Opts, true)},
    details =
    {present, proplists:get_value(details, Opts, false)},
    sync = {present, proplists:get_value(sync, Opts, true)},
    sync_timeout =
    proplists:get_value(sync_timeout, Opts, 0),
    max_batch_size =
    proplists:get_value(max_batch_size, Opts, 20)},
  {ok, State}.

handle_call({put, DataPoints, Options}, _From, State = #state{sync = Sync, max_batch_size = MaxBatchSize}) ->
  case proplists:get_value(sync, Options, Sync) of
    {present, true} ->
      {reply, put_(DataPoints, Options, State), State};
    {present, false} ->
      MaxBatchSize1 = proplists:get_value(max_batch_size, Options, MaxBatchSize),
      DataPoints1 = case DataPoints of
                      DataPoint when is_map(DataPoint) -> [DataPoint];
                      _ when is_list(DataPoints) -> DataPoints
                    end
        ++ drain_put(MaxBatchSize1, []),
      {reply, put_(DataPoints1, Options, State), State}
  end;
handle_call({version, Options}, _From, State = #state{server = Server0}) ->
  Server = proplists:get_value(server, Options, Server0),
  {reply,http_request(get, make_uri(Server, ["api/version"], []), <<>>), State};
handle_call(_Request, _From, State) ->
  {reply, ignored, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

preprocess(DataPoint) when is_map(DataPoint) ->
  case run_misc_steps([fun may_add_timestamp/1],
    DataPoint)
  of
    {ok, DataPoint1} -> DataPoint1;
    {error, Reason} -> error(Reason)
  end;
preprocess(DataPoints) when is_list(DataPoints) ->
  lists:map(fun (DataPoint) -> preprocess(DataPoint) end,
    DataPoints).

may_add_timestamp(#{timestamp := Timestamp})
  when is_integer(Timestamp) ->
  ok;
may_add_timestamp(DataPoint = #{timestamp := Timestamp})
  when is_binary(Timestamp) ->
  try erlang:binary_to_integer(Timestamp) of
    Timestamp1 -> {ok, DataPoint#{timestamp => Timestamp1}}
  catch
    error:_Reason ->
      {ok, DataPoint#{timestamp => unix_timestamp()}}
  end;
may_add_timestamp(DataPoint) ->
  {ok, DataPoint#{timestamp => unix_timestamp()}}.

run_misc_steps([], DataPoint) -> {ok, DataPoint};
run_misc_steps([Step | Steps], DataPoint) ->
  case Step(DataPoint) of
    ok -> run_misc_steps(Steps, DataPoint);
    {ok, DataPoint1} -> run_misc_steps(Steps, DataPoint1);
    {error, Reason} -> {error, Reason}
  end.

put_(DataPoints, Options0,
    #state{server = Server0, summary = Summary0,
      details = Details0, sync = Sync0,
      sync_timeout = SyncTimeout0}) ->
  Server = proplists:get_value(server, Options0, Server0),
  Sync = proplists:get_value(sync, Options0, Sync0),
  Options = [{summary,
    proplists:get_value(summary, Options0, Summary0)},
    {details,
      proplists:get_value(details, Options0, Details0)},
    {sync, Sync}],
  Options1 = case Sync of
               {present, true} ->
                 [{sync_timeout,
                   proplists:get_value(sync_timeout,
                     Options0,
                     SyncTimeout0)}
                   | Options];
               {present, false} -> Options
             end,
  http_request(post,
    make_uri(Server,
      ["api/put"],
      make_query_params(Options1)),
    jsx:encode(DataPoints)).

http_request(Method, Server, Payload) ->
  Headers = [{<<"Content-Type">>, <<"application/json">>}],
  Options = [{pool, default}, {connect_timeout, 10000}, {recv_timeout, 30000}, {follow_redirectm, true}, {max_redirect, 5}, with_body],
  case hackney:request(Method, Server, Headers, Payload, Options) of
    {ok, StatusCode, _Headers, ResponseBody} when StatusCode =:= 200 orelse StatusCode =:= 204 ->
      {ok, StatusCode, json_text_to_map(ResponseBody)};
    {ok, StatusCode, _Headers, ResponseBody} ->
      {error, {StatusCode, json_text_to_map(ResponseBody)}};
    {error, Reason} -> {error, Reason}
  end.

make_query_params(Options) ->
  lists:foldl(fun ({Flag, {present, true}}, QueryParams) ->
    QueryParams ++ [Flag];
    ({_Flag, {present, false}}, QueryParams) -> QueryParams;
    ({K, V}, QueryParams) -> QueryParams ++ [{K, V}]
              end,
    [],
    Options).

make_uri(Server, Paths, QueryParams) ->
  case list_to_binary(Server) of
    <<"http://", _/binary>> -> Server;
    <<"https://", _/binary>> -> Server;
    _ -> "http://" ++ Server
  end
  ++
    "/" ++
    filename:join(Paths) ++ "?" ++ serialize(QueryParams).

serialize(QueryParams) ->
  lists:foldl(fun ({K, V}, String) when is_atom(K) ->
    Query = erlang:atom_to_list(K) ++ "=" ++ v2str(V),
    case String of
      "" -> Query;
      _ -> String ++ "&" ++ Query
    end;
    (Flag, String) when is_atom(Flag) ->
      case String of
        "" -> erlang:atom_to_list(Flag);
        _ -> String ++ "&" ++ erlang:atom_to_list(Flag)
      end
              end,
    "",
    QueryParams).

v2str(V) when is_atom(V) -> erlang:atom_to_list(V);
v2str(V) when is_integer(V) ->
  erlang:integer_to_list(V).

json_text_to_map(JsonText) when is_list(JsonText) ->
  json_text_to_map(list_to_binary(JsonText));
json_text_to_map(JsonText) when is_binary(JsonText) ->
  case jsx:is_json(JsonText) of
    false -> #{};
    true ->
      jsx:decode(JsonText, [return_maps, {labels, atom}])
  end.

drain_put(0, Acc) -> Acc;
drain_put(Cnt, Acc) ->
  receive
    {async_put, DataPoint} when is_map(DataPoint) ->
      drain_put(Cnt - 1, [DataPoint] ++ [Acc]);
    {async_put, DataPoints} when is_list(DataPoints) ->
      drain_put(Cnt - 1, DataPoints ++ [Acc])
  after 0 -> Acc
  end.

atom_key_map(BinKeyMap) when is_map(BinKeyMap) ->
  maps:fold(fun (K, V, Acc) when is_binary(K) ->
    Acc#{binary_to_atom(K, utf8) => V};
    (K, V, Acc) -> Acc#{K => V}
            end,
    #{},
    BinKeyMap).
