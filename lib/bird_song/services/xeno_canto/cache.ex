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
end
