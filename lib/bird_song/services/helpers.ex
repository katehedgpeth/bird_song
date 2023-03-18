defmodule BirdSong.Services.Helpers do
  require Logger
  alias HTTPoison.{Response, Error}

  @type api_error() ::
          {:error, {:not_found, String.t()}}
          | {:error, {:bad_response, Response.t()}}
          | {:error, Error.t()}
  @type api_response(t) ::
          {:ok, t} | api_error()

  @spec parse_api_response({:ok, Response.t()} | {:error, Error.t()}, String.t()) ::
          api_response(Map.t())
  def parse_api_response(
        {:ok,
         %Response{
           status_code: 200,
           body: "" <> body
         }},
        "" <> _url
      ) do
    Jason.decode(body)
  end

  def parse_api_response(
        {:ok,
         %Response{
           status_code: 404
         }},
        "" <> url
      ) do
    {:error, {:not_found, url}}
  end

  def parse_api_response({:ok, %Response{} = response}, "" <> _url) do
    {:error, {:bad_response, response}}
  end

  def parse_api_response({:error, error}, "" <> _url) do
    {:error, error}
  end

  @spec log(Keyword.t() | Map.t(), atom(), atom()) :: :ok
  def log(args, module, level \\ :debug) do
    log_fn =
      case level do
        :debug -> &Logger.debug/1
        :info -> &Logger.info/1
        :warning -> &Logger.warning/1
        :error -> &Logger.error/1
      end

    [inspect([module]) | parse_log_args(args)]
    |> Enum.join(" ")
    |> log_fn.()
  end

  defp parse_log_args(args) do
    Enum.map(args, fn {key, val} -> "#{key}=#{inspect(val)}" end)
  end

  def get_env(app, key, default \\ :fetch!) do
    :bird_song
    |> Application.get_env(app)
    |> do_get_env(key, default)
  end

  defp do_get_env(env, key, :fetch!), do: Keyword.fetch!(env, key)
  defp do_get_env(env, key, default), do: Keyword.get(env, key, default)
end
