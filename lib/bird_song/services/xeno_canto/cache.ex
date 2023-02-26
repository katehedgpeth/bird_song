defmodule BirdSong.Services.XenoCanto.Cache do
  use BirdSong.Services.ThrottledCache, ets_opts: [:bag], ets_name: :xeno_canto

  alias BirdSong.{Bird, Services}
  alias Services.{Helpers, XenoCanto, XenoCanto.Response}

  # unfortunately it seems that this has to be public in order
  # for it to be called as a task in the :send_request call.
  def get_from_api(%Bird{sci_name: sci_name}) do
    sci_name
    |> XenoCanto.url()
    |> HTTPoison.get()
    |> Helpers.parse_api_response()
    |> case do
      {:ok, raw} ->
        {:ok, Response.parse(raw)}

      error ->
        error
    end
  end

  # used for saving data for tests
  def write_to_disk({:ok, response}, "" <> sci_name, true) do
    file_name =
      sci_name
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
