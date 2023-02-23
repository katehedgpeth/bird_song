defmodule BirdSong.MockApiCase do
  @moduledoc """
  Handles boilerplate of setting up mocks for external APIs using Bypass.

  Expects all services to have a :base_url config under the :bird_song config.

  use @tag service: :service_name to specify which service to mock.
  use @tag expect_once: &arity_fn/X to specify a Bypass.expect_once handler.
  use @tag expect: &arity_fn/X to specify a Bypass.expect handler.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import BirdSong.MockApiCase
    end
  end

  setup tags do
    case setup_bypass(tags) do
      {:ok, bypass: bypass} ->
        setup_mocks(tags, bypass)
        {:ok, bypass: bypass}

      :no_bypass ->
        :ok
    end
  end

  def setup_bypass(%{use_bypass: false}) do
    :no_bypass
  end

  def setup_bypass(%{service: service}) when is_atom(service) do
    bypass = Bypass.open()
    update_base_url(service, bypass)
    {:ok, bypass: bypass}
  end

  @type bypass_cb :: (Plug.Conn.t() -> Plug.Conn.t())

  @spec setup_mocks(
          %{
            optional(:expect_once) => bypass_cb(),
            optional(any) => any
          },
          Bypass.t()
        ) :: :ok
  def setup_mocks(%{expect_once: func}, %Bypass{} = bypass) when is_function(func),
    do: Bypass.expect_once(bypass, func)

  def setup_mocks(%{expect: func}, %Bypass{} = bypass) when is_function(func),
    do: Bypass.expect(bypass, func)

  def setup_mocks(%{stub: {"" <> method, "" <> path, func}}, %Bypass{} = bypass)
      when is_function(func),
      do: Bypass.stub(bypass, method, path, func)

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
