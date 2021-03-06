%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(emqx_auth_pgsql_cli).

-behaviour(ecpool_worker).

-include("emqx_auth_pgsql.hrl").

-include_lib("emqx/include/emqx.hrl").

-export([parse_query/1]).
-export([connect/1]).
-export([squery/1]).
-export([equery/2, equery/3]).

%%--------------------------------------------------------------------
%% Avoid SQL Injection: Parse SQL to Parameter Query.
%%--------------------------------------------------------------------

parse_query(undefined) ->
    undefined;
parse_query(Sql) ->
    case re:run(Sql, "'%[uca]'", [global, {capture, all, list}]) of
        {match, Variables} ->
            Params = [Var || [Var] <- Variables],
            {pgvar(Sql, Params), Params};
        nomatch ->
            {Sql, []}
    end.

pgvar(Sql, Params) ->
    Vars = ["$" ++ integer_to_list(I) || I <- lists:seq(1, length(Params))],
    lists:foldl(fun({Param, Var}, S) ->
            re:replace(S, Param, Var, [global, {return, list}])
        end, Sql, lists:zip(Params, Vars)).

%%--------------------------------------------------------------------
%% PostgreSQL Connect/Query
%%--------------------------------------------------------------------

connect(Opts) ->
    Host     = proplists:get_value(host, Opts),
    Username = proplists:get_value(username, Opts),
    Password = proplists:get_value(password, Opts),
    epgsql:connect(Host, Username, Password, conn_opts(Opts)).

conn_opts(Opts) ->
    conn_opts(Opts, []).
conn_opts([], Acc) ->
    Acc;
conn_opts([Opt = {database, _}|Opts], Acc) ->
    conn_opts(Opts, [Opt|Acc]);
conn_opts([Opt = {ssl, _}|Opts], Acc) ->
    conn_opts(Opts, [Opt|Acc]);
conn_opts([Opt = {port, _}|Opts], Acc) ->
    conn_opts(Opts, [Opt|Acc]);
conn_opts([Opt = {timeout, _}|Opts], Acc) ->
    conn_opts(Opts, [Opt|Acc]);
conn_opts([Opt = {ssl_opts, _}|Opts], Acc) ->
    conn_opts(Opts, [Opt|Acc]);
conn_opts([_Opt|Opts], Acc) ->
    conn_opts(Opts, Acc).

squery(Sql) ->
    ecpool:with_client(?APP, fun(C) -> epgsql:squery(C, Sql) end).

equery(Sql, Params) ->
    ecpool:with_client(?APP, fun(C) -> epgsql:equery(C, Sql, Params) end).

equery(Sql, Params, Credentials) ->
    ecpool:with_client(?APP, fun(C) -> epgsql:equery(C, Sql, replvar(Params, Credentials)) end).

replvar(Params, Credentials) ->
    replvar(Params, Credentials, []).

replvar([], _Credentials, Acc) ->
    lists:reverse(Acc);
replvar(["'%u'" | Params], Credentials = #{username := Username}, Acc) ->
    replvar(Params, Credentials, [Username | Acc]);
replvar(["'%c'" | Params], Credentials = #{client_id := ClientId}, Acc) ->
    replvar(Params, Credentials, [ClientId | Acc]);
replvar(["'%a'" | Params], Credentials = #{peername := {IpAddr, _}}, Acc) ->
    replvar(Params, Credentials, [inet_parse:ntoa(IpAddr) | Acc]);
replvar([Param | Params], Credentials, Acc) ->
    replvar(Params, Credentials, [Param | Acc]).

