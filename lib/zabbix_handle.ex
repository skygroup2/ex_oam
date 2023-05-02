defmodule Skn.Run.ZabbixHandle do
  @moduledoc """
    zabbix api for serving agent
  """
  require Logger

  def init(req, opts) do
    handle(req, opts)
  end

  def route_and_process("/counter", req) do
    vars = :cowboy_req.parse_qs(req)
    {_, name_str} = List.keyfind(vars, "name", 0, {"name", nil})
    counter_type_mod = Skn.Config.get(:web_stats_counter_type_mod, nil)
    reset = if counter_type_mod != nil and is_atom(counter_type_mod)
       and function_exported?(counter_type_mod, :counter_type, 1) do
      apply(counter_type_mod, :counter_type, [name_str])
    else
      1
    end
    return_ct = check_and_read_counter(name_str, reset)
    {200, "#{return_ct}", "text/html"}
  end

  def route_and_process("/discovery", _req) do
    data = Skn.Config.get(:web_stats_discover_data, %{})
    {200, %{"data" => data} |> Jason.encode!(), "application/json"}
  end

  def route_and_process(_path, _req) do
    {404, "0", "text/html"}
  end

  def check_and_read_counter(name, reset) do
    cond do
      reset == 1 ->
        # normal counter
        atom_name = String.to_existing_atom(name)
        Skn.Counter.read_and_reset(atom_name)
      reset == 2 ->
        # avg, min, max counter
        len = byte_size(name)
        base = String.slice(name, 0, len - 4)
        atom_name = String.to_existing_atom(name)
        count_name = String.to_existing_atom(base <> "_count")
        other_name = Enum.reduce(["_avg", "_min", "_max"], [], fn(x, acc) ->
          xx = base <> x
          if xx != name, do: [String.to_existing_atom(xx)| acc], else: acc
        end)
        Skn.Counter.read_avg_min_max(atom_name, other_name, count_name)
      true ->
        # don't reset counter
        atom_name = String.to_existing_atom(name)
        Skn.Counter.read(atom_name)
    end
  end

  def handle(req, state) do
    try do
      path = :cowboy_req.path(req)
      {code, body, content_type} = route_and_process(path, req)
      headers = %{"content-type" => content_type}
      new_req = :cowboy_req.reply(code, headers, body, req)
      {:ok, new_req, state}
    catch
      _, exp ->
        Logger.error "exception #{inspect exp} / #{inspect __STACKTRACE__}"
        headers = %{"content-type" => "text/html"}
        new_req = :cowboy_req.reply(500, headers, "0", req)
        {:ok, new_req, state}
    end
  end
end