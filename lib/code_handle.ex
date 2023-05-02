defmodule Skn.Run.CodeServer do
  @moduledoc """
    sync code between dev and prod
  """
  require Logger

  def run_sync_as(bot_ids, fun, spawn \\ 20) do
    bot_ids = Enum.to_list(bot_ids)
    size = max(trunc(length(bot_ids) / spawn), 1)
    ss = Enum.chunk_every(Enum.sort(bot_ids), size)
    parent = self()
    Enum.each ss, fn x ->
      spawn(
        fn ->
          Enum.each(x, fn xx ->
            ret = fun.(xx)
            send(parent, {:return, ret})
          end)
        end
      )
    end
    run_sync_result(%{}, length(bot_ids))
  end

  defp run_sync_result(acc, remain) do
    receive do
      {:return, status} ->
        counter = Map.get(acc, status, 0) + 1
        new_acc = Map.put(acc, status, counter)
        if remain > 1 do
          run_sync_result(new_acc, remain - 1)
        else
          new_acc
        end
    end
  end

  def bot_sync_keys() do
    url = "http://127.0.0.1:#{get_sync_port()}/sync_bot_keys?app=#{Skn.Config.get(:app)}"
    headers = %{"connection" => "close"}
    try do
      case GunEx.http_request("GET", url, headers, "", GunEx.default_option(), nil) do
        %{status_code: 200, body: body} ->
          keys = Jason.decode!(body)["keys"]
          keys
        _ ->
          []
      end
    catch
      _, exp ->
        Logger.error("bot keys download #{inspect exp}/ #{inspect __STACKTRACE__}")
        []
    end
  end

  def bot_sync_with_prod(bot_id, :write) do
#    Logger.debug("bot #{bot_id} upload")
    %{config: config} = Skn.Bot.read(bot_id)
    url = "http://127.0.0.1:#{get_sync_port()}/sync_bot_write?id=#{bot_id}&app=#{Skn.Config.get(:app)}"
    headers = %{"connection" => "close"}
    bin = :erlang.term_to_binary(config)
    try do
      case GunEx.http_request("POST", url, headers, bin, GunEx.default_option(), nil) do
        %{status_code: 200, body: body} ->
          ok = Jason.decode!(body)["error_code"] == 0
          if ok == true do
            Logger.info("bot #{bot_id} uploaded")
          else
            Logger.error("bot #{bot_id} upload wrong_body")
          end
          ok
        _ ->
          Logger.error("bot #{bot_id} upload wrong_ret")
          false
      end
    catch
      _, exp ->
        Logger.error("bot #{bot_id} upload #{inspect exp}/ #{inspect __STACKTRACE__}")
        false
    end
  end

  def bot_sync_with_prod(bot_id, :read) do
#    Logger.debug("bot #{bot_id} download")
    url = "http://127.0.0.1:#{get_sync_port()}/sync_bot_read?id=#{bot_id}&app=#{Skn.Config.get(:app)}"
    headers = %{"connection" => "close"}
    try do
      case GunEx.http_request("GET", url, headers, "", GunEx.default_option(), nil) do
        %{status_code: 200, body: body} ->
          config = :erlang.binary_to_term(body)
          if is_map(config) do
            Logger.info("bot #{bot_id} downloaded")
            Skn.Bot.write({bot_id, config})
          else
            Logger.error("bot #{bot_id} download wrong_body")
          end
          true
        _ ->
          Logger.error("bot #{bot_id} download wrong_ret")
          false
      end
    catch
      _, exp ->
        Logger.error("bot #{bot_id} download #{inspect exp}/ #{inspect __STACKTRACE__}")
        false
    end
  end

  def code_sync(module)  do
    Enum.map(List.wrap(get_sync_port()), fn x ->
      {x, do_code_sync(x, module)}
    end)
  end

  def do_code_sync(port, module) do
    url = "http://127.0.0.1:#{port}/sync_code?module=#{module}&app=#{Skn.Config.get(:app)}"
    headers = %{"connection" => "close"}
    try do
      path = :code.which(module)
      bin = File.read!(path)
      case GunEx.http_request("POST", url, headers, bin, GunEx.default_option(), nil) do
        %{status_code: 200, body: body} ->
          if Jason.decode!(body)["error_code"] == 0 do
            true
          else
            false
          end
        _ ->
          false
      end
    catch
      _, exp ->
        Logger.error("sync exception #{inspect exp}/ #{inspect __STACKTRACE__}")
        false
    end
  end

  def get_sync_port(), do: Skn.Config.get(:http_code_connect_port, 8086)

  def init(req, state) do
    handle(req, state)
  end

  def process_by_path("/sync_bot_keys", req, state) do
    qs = :cowboy_req.parse_qs(req)
    {_, app} = List.keyfind(qs, "app", 0)
    Logger.debug("sync bot keys")
    if app == Skn.Config.get(:app) do
      keys = :mnesia.dirty_all_keys(:bot_record) |> Enum.sort()
      headers = %{"content-type" => "application/json"}
      next_req = :cowboy_req.reply(200, headers, Jason.encode!(%{keys: keys}), req)
      {:ok, next_req, state}
    else
      throw({:error, :wrong_app})
    end
  end

  def process_by_path("/sync_bot_write", req, state) do
    qs = :cowboy_req.parse_qs(req)
    {_, id} = List.keyfind(qs, "id", 0)
    {_, app} = List.keyfind(qs, "app", 0)
    Logger.debug("sync bot #{id} write")
    if app == Skn.Config.get(:app) do
      {:ok, body, _} = :cowboy_req.read_body(req)
      config = :erlang.binary_to_term(body)
      Skn.Bot.write({id, config})
      headers = %{"content-type" => "application/json"}
      next_req = :cowboy_req.reply(200, headers, Jason.encode!(%{error_code: 0, error_msg: "OK"}), req)
      {:ok, next_req, state}
    else
      throw({:error, :wrong_app})
    end
  end

  def process_by_path("/sync_bot_read", req, state) do
    qs = :cowboy_req.parse_qs(req)
    {_, id} = List.keyfind(qs, "id", 0)
    {_, app} = List.keyfind(qs, "app", 0)
    Logger.debug("sync bot #{id} read")
    if app == Skn.Config.get(:app) do
      config = Skn.Bot.read(id)[:config]
      bin = :erlang.term_to_binary(config)
      headers = %{"content-type" => "application/octet-stream"}
      next_req = :cowboy_req.reply(200, headers, bin, req)
      {:ok, next_req, state}
    else
      throw({:error, :wrong_app})
    end
  end

  def process_by_path("/sync_code", req, state) do
    qs = :cowboy_req.parse_qs(req)
    {_, module} = List.keyfind(qs, "module", 0)
    {_, app} = List.keyfind(qs, "app", 0)
    module_name = String.to_existing_atom(module)
    path = :code.which(module_name)
    Logger.debug("sync_code #{module_name} : #{inspect path}")
    if app == Skn.Config.get(:app) and path != [] do
      {:ok, body, _} = :cowboy_req.read_body(req)
      File.write!(path, body, [:binary])
      IEx.Helpers.l(module_name)
      headers = %{"content-type" => "application/json"}
      next_req = :cowboy_req.reply(200, headers, Jason.encode!(%{error_code: 0, error_msg: "OK"}), req)
      {:ok, next_req, state}
    else
      throw({:error, :wrong_app})
    end
  end

  def handle(req, state) do
    try do
      path = :cowboy_req.path(req)
      process_by_path(path, req, state)
    catch
      _, exp ->
        Logger.error "Exception: #{inspect __STACKTRACE__}"
        headers = %{"content-type" => "application/json"}
        error_msg = "#{inspect exp}"
        req2 = :cowboy_req.reply(500, headers, Jason.encode!(%{error_code: 500, error_msg: error_msg}), req)
        {:ok, req2, state}
    end
  end
end
