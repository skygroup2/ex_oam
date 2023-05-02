defmodule Skn.Run do
  @moduledoc """
  Documentation for `SknRun`.
  """

  def start_zabbix_server() do
    http_port = Skn.Config.get(:http_zabbix_server_port, -1)
    module = Skn.Config.get(:web_stats_mod, Skn.Stats.RestApi)
    if is_integer(http_port) and http_port > 1024 and http_port < 65535 do
      dispatch = :cowboy_router.compile([{:_, [{:_, module, []}]}])
      :cowboy.start_clear(:http, [{:port, http_port}], %{env: %{dispatch: dispatch}})
    else
      {:ok, :ignore}
    end
  end

  def start_code_server() do
    code_port = Skn.Config.get(:http_code_server_port, -1)
    if is_integer(code_port) and code_port > 1024 and code_port < 65535 do
      dispatch = :cowboy_router.compile([
        {:_, [
          {:_, Skn.Run.CodeServer, %{}},
        ]}
      ])
      :persistent_term.put(:mt5_dispatch, dispatch)
      ranch_opts = %{
        num_acceptors: 2,
        max_connections: :infinity,
        socket_opts: [
          {:port, Skn.Config.get(:http_code_server_port, code_port)}
        ]
      }
      :cowboy.start_clear(:mt5_http, ranch_opts, %{env: %{dispatch: {:persistent_term, :mt5_dispatch}}})
    else
      :skip
    end
  end

  def set_stats_counter_type_mod(mod) do
    Skn.Config.set(:web_stats_counter_type_mod, mod)
  end

  def register_stats_discover(data) do
    Skn.Config.set(:web_stats_discover_data, data)
  end
end
