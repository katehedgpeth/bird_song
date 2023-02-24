defmodule BirdSong.Services.Helpers do
  require Logger
  alias HTTPoison.{Request, Response, Error}

  @type api_response(t) ::
          {:ok, t}
          | {:error, Response.t()}
          | {:error, Error.t()}

  @spec parse_api_response({:ok, Response.t()} | {:error, Error.t()}) ::
          api_response(any)
  def parse_api_response(
        {:ok,
         %Response{
           status_code: 200,
           body: "" <> body,
           request: %Request{url: url}
         }}
      ) do
    Logger.debug("request_status=success url=" <> url)
    Jason.decode(body)
  end

  def parse_api_response(
        {:ok,
         %Response{
           status_code: 404,
           request: %Request{url: url}
         } = response}
      ) do
    log_error(response)
    {:error, {:not_found, url}}
  end

  def parse_api_response({:ok, %Response{} = response}) do
    log_error(response)
    {:error, {:bad_response, response}}
  end

  def parse_api_response({:error, error}) do
    log_error(error)
    {:error, error}
  end

  def get_env(app, key, default \\ :fetch!) do
    :bird_song
    |> Application.get_env(app)
    |> do_get_env(key, default)
  end

  defp do_get_env(env, key, :fetch!), do: Keyword.fetch!(env, key)
  defp do_get_env(env, key, default), do: Keyword.get(env, key, default)

  defp log_error(%Response{status_code: code, request: %Request{url: url}}) do
    Logger.error("request_status=error status_code=#{code} url=" <> url)
  end

  defp log_error(%Error{reason: reason}) do
    Logger.error("request_status=error status_code=unknown url=unknown error=#{reason}")
  end
end
