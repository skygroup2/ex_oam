defmodule Skn.Run do
  @moduledoc """
  Documentation for `SknRun`.
  """

  def start_zabbix_server() do
    http_port = Skn.Config.get(:http_zabbix_server_port, -1)
    if is_integer(http_port) and http_port > 1024 and http_port < 65535 do
      dispatch = :cowboy_router.compile([
        {:_, [
          {:_, Skn.Config.get(:http_zabbix_server_mod, Skn.Run.ZabbixHandle), []}
        ]}
      ])
      ranch_opts = %{
        num_acceptors: 2,
        max_connections: :infinity,
        socket_opts: [
          {:port, http_port}
        ]
      }
      :persistent_term.put(:zabbix_dispatch, dispatch)
      :cowboy.start_clear(:zabbix_http, ranch_opts, %{env: %{dispatch: {:persistent_term, :zabbix_dispatch}}})
    else
      {:ok, :ignore}
    end
  end

  def start_code_server() do
    code_port = Skn.Config.get(:http_code_server_port, -1)
    if is_integer(code_port) and code_port > 1024 and code_port < 65535 do
      dispatch = :cowboy_router.compile([
        {:_, [
          {'/:app_node/[...]', Skn.Config.get(:http_code_server_mode, Skn.Run.CodeServer), %{}},
        ]}
      ])
      ranch_opts = %{
        num_acceptors: 2,
        max_connections: :infinity,
        socket_opts: [
          {:port, code_port}
        ]
      }
      :persistent_term.put(:code_dispatch, dispatch)
      :cowboy.start_clear(:code_http, ranch_opts, %{env: %{dispatch: {:persistent_term, :code_dispatch}}})
    else
      :skip
    end
  end

  def set_zabbix_counter_type_mod(mod) do
    Skn.Config.set(:zabbix_counter_type_mod, mod)
  end

  def register_zabbix_discover(data) do
    Skn.Config.set(:zabbix_discover_data, data)
  end
end
