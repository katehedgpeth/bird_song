defmodule BirdSongWeb.Api.V1.RegionController do
  use BirdSongWeb, :controller

  alias BirdSong.Region

  def index(conn, %{"name" => <<_::binary-size(3), _::binary>> = name}) do
    json(conn, %{regions: Region.filter_by_name(name)})
  end

  def index(conn, params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: true,
      message: error_message(params)
    })
  end

  def error_message(%{"name" => _}), do: "Name must be at least 3 characters."
  def error_message(%{}), do: "Missing required parameter: name"
end
