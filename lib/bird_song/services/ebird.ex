defmodule BirdSong.Services.Ebird do
  require Logger
  alias BirdSong.Services.Helpers
  alias __MODULE__.Observation

  @token :bird_song
         |> Application.compile_env(:ebird)
         |> Keyword.fetch!(:token)

  def url(endpoint) do
    :ebird
    |> Helpers.get_env(:base_url)
    |> List.wrap()
    |> Enum.concat(["v2", endpoint])
    |> Path.join()
  end

  @spec get_recent_observations(String.t()) :: Helpers.api_response(List.t(Observation.t()))
  def get_recent_observations("" <> region) do
    url =
      "data/obs"
      |> Path.join([region])
      |> Path.join(["recent"])
      |> url()

    url
    |> send_request([{"back", 30}])
    |> case do
      {:ok, observations} ->
        {:ok, Enum.map(observations, &Observation.parse/1)}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec send_request(String.t(), List.t({String.t(), any})) :: Helpers.api_response(List.t())
  defp send_request(url, params) do
    Logger.debug("event=send_request url=" <> url)

    url
    |> HTTPoison.get([{"x-ebirdapitoken", @token}], params: params)
    |> Helpers.parse_api_response()
  end
end
