defmodule BirdSong.Services.XenoCanto.Cache do
  use BirdSong.Services.ThrottledCache, ets_name: :xeno_canto

  alias BirdSong.Services
  alias Services.{Helpers, XenoCanto, XenoCanto.Response}

  # unfortunately it seems that this has to be public in order
  # for it to be called as a task in the :send_request call.
  @spec get_recording_from_api(binary, any) ::
          {:error,
           %{
             :__struct__ => HTTPoison.Error | HTTPoison.Response,
             optional(:__exception__) => true,
             optional(:body) => any,
             optional(:headers) => list,
             optional(:id) => nil | reference,
             optional(:reason) => any,
             optional(:request) => HTTPoison.Request.t(),
             optional(:request_url) => any,
             optional(:status_code) => integer
           }}
          | {:ok, any}
  def get_recording_from_api("" <> bird, server) do
    Logger.debug("message=sending_request service=xeno_canto bird=" <> bird)

    bird
    |> XenoCanto.url()
    |> HTTPoison.get()
    |> Helpers.parse_api_response()
    |> case do
      {:ok, raw} ->
        recording = Response.parse(raw)
        GenServer.cast(server, {:save, {bird, recording}})
        {:ok, recording}

      error ->
        error
    end
  end

  # used for saving data for tests
  def write_to_disk({:ok, response}, bird, true) do
    file_name =
      bird
      |> String.replace(" ", "_")
      |> Kernel.<>(".json")

    "test/mock_data/"
    |> Kernel.<>(file_name)
    |> Path.relative_to_cwd()
    |> File.write!(Jason.encode!(response))

    {:ok, response}
  end

  def write_to_disk(response, _, false), do: response
end
