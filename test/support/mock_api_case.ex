defmodule BirdSong.MockApiCase do
  @moduledoc """
  Handles boilerplate of setting up mocks for external APIs using Bypass.

  Expects all services to have a :base_url config under the :bird_song config.

  use @tag service: :service_name to specify which service to mock.
  use @tag expect_once: &arity_fn/X to specify a Bypass.expect_once handler.
  use @tag expect: &arity_fn/X to specify a Bypass.expect handler.
  """
  use ExUnit.CaseTemplate
  alias BirdSong.TestHelpers
  alias BirdSong.Services.XenoCanto
  alias BirdSongWeb.QuizLive.Caches

  using do
    quote do
      import BirdSong.MockApiCase
      alias BirdSong.{Bird, TestHelpers}
      alias Plug.Conn

      @red_shouldered_hawk %Bird{sci_name: "Buteo lineatus", common_name: "Red-shouldered Hawk"}
      @carolina_wren %Bird{sci_name: "Thryothorus ludovicianus", common_name: "Carolina Wren"}
      @eastern_bluebird %Bird{sci_name: "Sialia sialis", common_name: "Eastern Bluebird"}

      @recordings Enum.reduce(
                    [
                      @red_shouldered_hawk,
                      @carolina_wren,
                      @eastern_bluebird
                    ],
                    %{},
                    fn %Bird{sci_name: sci_name}, acc ->
                      Map.put(acc, sci_name, TestHelpers.read_mock_file(sci_name))
                    end
                  )

      @images TestHelpers.read_mock_file("flickr_" <> @red_shouldered_hawk.common_name)
    end
  end

  setup tags do
    {:ok, xeno_canto} = TestHelpers.start_cache(XenoCanto.Cache)
    caches = %Caches{xeno_canto: xeno_canto}

    case setup_bypass(tags) do
      {:ok, bypass: bypass} ->
        setup_mocks(tags, bypass)
        {:ok, bypass: bypass, caches: caches}

      :no_bypass ->
        {:ok, caches: caches}
    end
  end

  def setup_bypass(%{use_bypass: false}) do
    :no_bypass
  end

  def setup_bypass(%{services: services}) when is_list(services) do
    bypass = Bypass.open()
    Enum.each(services, &update_base_url(&1, bypass))
    {:ok, bypass: bypass}
  end

  @type bypass_generic_cb :: (Plug.Conn.t() -> Plug.Conn.t())
  @type bypass_path_cb :: {String.t(), String.t(), bypass_generic_cb()}

  @spec setup_mocks(
          %{
            optional(:expect_once) => bypass_generic_cb() | List.t(bypass_generic_cb()),
            optional(:expect) => bypass_generic_cb() | List.t(bypass_generic_cb()),
            optional(:stub) => bypass_path_cb() | List.t(bypass_path_cb()),
            optional(any) => any
          },
          Bypass.t()
        ) :: :ok
  def setup_mocks(%{expect_once: func}, %Bypass{} = bypass) when is_function(func),
    do: Bypass.expect_once(bypass, func)

  def setup_mocks(
        %{expect_once: [{"" <> _, "" <> _, func} | _] = funcs},
        %Bypass{} = bypass
      )
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} ->
          Bypass.expect_once(bypass, method, path, func)
        end)

  def setup_mocks(%{expect: func}, %Bypass{} = bypass) when is_function(func),
    do: Bypass.expect(bypass, func)

  def setup_mocks(
        %{expect: [{"" <> _, "" <> _, func} | _] = funcs},
        %Bypass{} = bypass
      )
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} -> Bypass.expect(bypass, method, path, func) end)

  def setup_mocks(%{stub: {"" <> method, "" <> path, func}}, %Bypass{} = bypass)
      when is_function(func),
      do: Bypass.stub(bypass, method, path, func)

  def setup_mocks(%{stub: [{"" <> _, "" <> _, func} | _] = funcs}, %Bypass{} = bypass)
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} ->
          Bypass.stub(bypass, method, path, func)
        end)

  def setup_mocks(%{use_mock: false}, %Bypass{}), do: :ok

  def update_base_url(service_name, %Bypass{} = bypass) do
    do_update_base_url(service_name, mock_url(bypass))
  end

  def update_base_url(service_name, "" <> url) do
    do_update_base_url(service_name, url)
  end

  defp do_update_base_url(service_name, url) do
    env =
      :bird_song
      |> Application.get_env(service_name)
      |> Keyword.replace!(:base_url, url)

    Application.put_env(:bird_song, service_name, env)
  end

  def mock_url(%Bypass{port: port}), do: "http://localhost:#{port}"
end
