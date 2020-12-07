{application,opentsdb,
             [{description,"OpenTSDB Client"},
              {vsn,"0.5.0"},
              {modules,[opentsdb, opentsdb_app, opentsdb_sup]},
              {registered,[opentsdb_sup]},
              {applications,[kernel,stdlib,jsx,hackney]},
              {mod,{opentsdb_app,[]}}]}.

%% jsx erlang json lib

%% hackney simple HTTP client in Erlang




%% {ok,{_,[{abstract_code,{_,AC}}]}} = beam_lib:chunks(Beam,[abstract_code]).
%% io:fwrite("~s~n", [erl_prettypr:format(erl_syntax:form_list(AC))]).

%%{ok,{_,[{abstract_code,{_,AC}}]}} = beam_lib:chunks(emqx_bridge_rocket,[abstract_code]).
%%{ok,{_,[{abstract_code,{_,AC}}]}} = beam_lib:chunks(opentsdb,[abstract_code]).




