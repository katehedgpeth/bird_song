defmodule BirdSong.Services.Helpers do
  @type api_response(t) ::
          {:ok, t}
          | {:error, HTTPoison.Response.t()}
          | {:error, HTTPoison.Error.t()}

  @spec parse_api_response({:ok, HTTPoison.Response.t()} | {:error, HTTPoison.Error.t()}) ::
          api_response(any)
  def parse_api_response({:ok, %HTTPoison.Response{status_code: 200, body: "" <> body}}),
    do: Jason.decode(body)

  def parse_api_response(
        {:ok, %HTTPoison.Response{status_code: 404, request: %HTTPoison.Request{url: url}}}
      ),
      do: {:error, {:not_found, url}}

  def parse_api_response({:ok, %HTTPoison.Response{} = response}),
    do: {:error, {:bad_response, response}}

  def parse_api_response(error), do: error

  def get_env(app, key, default \\ :fetch!) do
    :bird_song
    |> Application.get_env(app)
    |> do_get_env(key, default)
  end

  defp do_get_env(env, key, :fetch!), do: Keyword.fetch!(env, key)
  defp do_get_env(env, key, default), do: Keyword.get(env, key, default)
end
