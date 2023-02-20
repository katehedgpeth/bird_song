defmodule BirdSong.Services.Ebird do
  alias __MODULE__.Observation

  @token :bird_song
         |> Application.compile_env(:ebird)
         |> Keyword.fetch!(:token)

  @type response(t) ::
          {:ok, t} | {:error, HTTPoison.Response.t()} | {:error, HTTPoison.Error.t()}

  def url(endpoint) do
    :bird_song
    |> Application.get_env(:ebird)
    |> Keyword.fetch!(:base_url)
    |> List.wrap()
    |> Enum.concat(["v2", endpoint])
    |> Path.join()
  end

  @spec get_recent_observations(String.t()) :: response(List.t(Observation.t()))
  def get_recent_observations("" <> region) do
    "data/obs"
    |> Path.join([region])
    |> Path.join(["recent"])
    |> url()
    |> send_request([{"back", 30}])
    |> case do
      {:ok, observations} -> {:ok, Enum.map(observations, &Observation.parse/1)}
      {:error, error} -> {:error, error}
    end
  end

  @spec send_request(String.t(), List.t({String.t(), any})) :: response(List.t())
  defp send_request(url, params) do
    url
    |> HTTPoison.get([{"x-ebirdapitoken", @token}], params: params)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: "" <> body}} ->
        Jason.decode(body)

      {:ok, %HTTPoison.Response{status_code: 404, request: %HTTPoison.Request{url: url}}} ->
        {:error, {:not_found, url}}

      {:ok, %HTTPoison.Response{} = response} ->
        {:error, {:bad_response, response}}

      error ->
        error
    end
  end
end
