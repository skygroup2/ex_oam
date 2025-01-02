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

  defp default_proxy_option, do: CQ.HttpEx.sync_proxy_option(%{}, 25_000, 90_000)
  defp make_request(method, url, headers, body) do
    CQ.HttpEx.request("CODE", method, url, headers, body, default_proxy_option(), 0, [], nil)
  end

  def bot_sync_keys(dst_port \\ nil, dst_path \\ nil) do
    url = make_url(dst_port, dst_path) <> "/sync_bot_keys?app=#{Skn.Config.get(:app)}"
    headers = %{"connection" => "close"}
    try do
      case make_request("GET", url, headers, "") do
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

  def bot_write_to_prod(bot_id, dst_port \\ nil, dst_path \\ nil) do
    %{config: config} = Skn.Bot.read(bot_id)
    url = make_url(dst_port, dst_path) <> "/sync_bot_write?id=#{bot_id}&app=#{Skn.Config.get(:app)}"
    headers = %{"connection" => "close"}
    bin = :erlang.term_to_binary(config)
    try do
      case make_request("POST", url, headers, bin) do
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

  def bot_read_from_prod(bot_id, dst_port \\ nil, dst_path \\ nil) do
    url = make_url(dst_port, dst_path) <> "/sync_bot_read?id=#{bot_id}&app=#{Skn.Config.get(:app)}"
    headers = %{"connection" => "close"}
    try do
      case make_request("GET", url, headers, "") do
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

  def make_url({dst_port, dst_path}), do: make_url(dst_port, dst_path)
  def make_url({dst_host, dst_port, dst_path}), do: make_url(dst_host, dst_port, dst_path)
  def make_url(dst_port, dst_path) do
    make_url(Skn.Config.get(:http_code_connect_host, "127.0.0.1"), dst_port, dst_path)
  end
  def make_url(dst_host, dst_port, dst_path) do
    dst_port = if dst_port == nil, do: Skn.Config.get(:http_code_connect_port, 8086), else: dst_port
    dst_path = if dst_path == nil, do: Skn.Config.get(:http_code_connect_path, nil), else: dst_path
    if dst_path == nil do
      "http://#{dst_host}:#{dst_port}"
    else
      "http://#{dst_host}:#{dst_port}/#{dst_path}"
    end
  end

  defp format_target_srv(nil) do
    {Skn.Config.get(:http_code_connect_host, "127.0.0.1"), Skn.Config.get(:http_code_connect_port, 8086), Skn.Config.get(:http_code_connect_path, nil)}
  end
  defp format_target_srv(target), do: target

  def code_sync(modules, targets \\ nil)
  def code_sync(modules, targets) when is_list(modules) do
    Enum.each(modules, fn x -> code_sync(x, targets, 0) end)
    code_reload(modules, targets)
  end
  def code_sync(module, targets) do
    code_sync(module, targets, 1)
  end

  def code_sync(module, targets, reload) when is_atom(module)  do
    dst_pair = format_target_srv(targets)
    Enum.map(List.wrap(dst_pair), fn target ->
      {target, do_code_sync(module, target, reload)}
    end)

  end

  def code_reload(modules, targets) do
    dst_pair = format_target_srv(targets)
    Enum.map(List.wrap(dst_pair), fn target ->
      {target, do_code_reload(modules, target)}
    end)
  end

  def do_code_reload(modules, target) do
    url = make_url(target) <> "/reload_code?app=#{Skn.Config.get(:app)}"
    headers = %{"connection" => "close"}
    case make_request("POST", url, headers, Jason.encode!(%{modules: modules})) do
      %{status_code: 200, body: body} ->
        Jason.decode!(body)
      _exp ->
        false
    end
  catch
    _, _exp ->
      false
  end

  def do_code_sync(module, target, reload) do
    url = make_url(target) <> "/sync_code?module=#{module}&app=#{Skn.Config.get(:app)}&reload=#{reload}"
    headers = %{"connection" => "close"}
    try do
      path = :code.which(module)
      bin = File.read!(path)
      case make_request("POST", url, headers, bin) do
        %{status_code: 200, body: body} ->
          Jason.decode!(body)["error_code"] == 0
        _exp ->
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

  def process_by_path("/reload_code", req, state) do
    qs = :cowboy_req.parse_qs(req)
    {_, app} = List.keyfind(qs, "app", 0)
    if app == Skn.Config.get(:app) do
      {:ok, body, _} = :cowboy_req.read_body(req)
      %{"modules" => modules} = Jason.decode!(body)
      ret = Enum.map(modules, fn x ->
        try do
          module_name = String.to_existing_atom(x)
          IEx.Helpers.l(module_name)
          %{m: x, reload: true}
        catch
          _, _exp ->
            %{m: x, reload: false}
        end
      end)
      headers = %{"content-type" => "application/json"}
      next_req = :cowboy_req.reply(200, headers, Jason.encode!(%{error_code: 0, error_msg: "OK", results: ret}), req)
      {:ok, next_req, state}
    else
      throw({:error, :wrong_app})
    end
  end

  def process_by_path("/sync_code", req, state) do
    qs = :cowboy_req.parse_qs(req)
    {_, module} = List.keyfind(qs, "module", 0)
    {_, app} = List.keyfind(qs, "app", 0)
    {_, reload} = List.keyfind(qs, "reload", 0, {"reload", "1"})
    module_name = String.to_existing_atom(module)
    path = :code.which(module_name)
    Logger.debug("sync_code #{module_name} : #{inspect path}")
    if app == Skn.Config.get(:app) and path != [] do
      {:ok, body, _} = :cowboy_req.read_body(req)
      File.write!(path, body, [:binary])
      if reload == "1" do
        IEx.Helpers.l(module_name)
      end
      headers = %{"content-type" => "application/json"}
      next_req = :cowboy_req.reply(200, headers, Jason.encode!(%{error_code: 0, error_msg: "OK"}), req)
      {:ok, next_req, state}
    else
      throw({:error, :wrong_app})
    end
  end

  def handle(req, state) do
    try do
      sub_path = "/" <> Enum.join(:cowboy_req.path_info(req), "/")
      process_by_path(sub_path, req, state)
    catch
      _, exp ->
        Logger.error("Exception: #{inspect __STACKTRACE__}")
        headers = %{"content-type" => "application/json"}
        error_msg = "#{inspect exp}"
        req2 = :cowboy_req.reply(500, headers, Jason.encode!(%{error_code: 500, error_msg: error_msg}), req)
        {:ok, req2, state}
    end
  end
end
