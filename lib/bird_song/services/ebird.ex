defmodule BirdSong.Services.Ebird do
  @token :bird_song
         |> Application.compile_env(:ebird)
         |> Keyword.fetch!(:token)

  def url(endpoint) do
    :bird_song
    |> Application.get_env(:ebird)
    |> Keyword.fetch!(:base_url)
    |> List.wrap()
    |> Enum.concat(["v2", endpoint])
    |> Path.join()
  end

  def get_region_list("" <> region) do
    "product/spplist"
    |> Path.join([region])
    |> url()
    |> HTTPoison.get([{"x-ebirdapitoken", @token}])
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: "" <> body}} ->
        Jason.decode(body)

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, {:not_found, region}}

      {:ok, %HTTPoison.Response{} = response} ->
        {:error, {:bad_response, response}}

      error ->
        error
    end
  end
end
