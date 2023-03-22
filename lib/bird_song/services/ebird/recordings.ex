defmodule BirdSong.Services.Ebird.Recordings.UnknownMessageError do
  defexception [:data]

  def message(%__MODULE__{data: data}) do
    """
    Received unexpected message from port:
    #{inspect(data)}
    """
  end
end

defmodule BirdSong.Services.Ebird.Recordings do
  use BirdSong.Services.ThrottledCache, ets_opts: [], ets_name: :ebird_recordings

  alias BirdSong.{
    Bird,
    Services.Helpers
  }

  alias __MODULE__.{
    Response,
    Playwright
  }

  alias BirdSong.Services.ThrottledCache, as: TC

  def base_url() do
    Helpers.get_env(__MODULE__, :base_url)
  end

  def url(%Bird{} = bird) do
    base_url()
    |> URI.parse()
    |> Map.put(:path, "/catalog")
    |> Map.put(:query, bird |> params() |> URI.encode_query())
    |> URI.to_string()
  end

  def params(%Bird{species_code: code}) do
    [
      {"taxonCode", code},
      {"mediaType", "audio"}
    ]
  end

  def get_from_api(%Bird{} = bird, %TC.State{}) do
    {:ok, server} =
      DynamicSupervisor.start_child(
        Services.GenServers,
        {Playwright, bird: bird, parent: self()}
      )

    response = Playwright.run(server)
    DynamicSupervisor.terminate_child(Services.GenServers, server)

    case response do
      {:ok, [_ | _] = raw_recordings} -> {:ok, Response.parse(raw_recordings)}
      {:error, error} -> {:error, error}
    end
  end
end
