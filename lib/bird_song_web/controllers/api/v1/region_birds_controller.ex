defmodule BirdSongWeb.Api.V1.RegionBirdsController do
  use BirdSongWeb, :controller

  alias Plug.Conn

  alias BirdSong.{Bird, Services, Region}
  alias BirdSong.Services.Ebird.RegionSpeciesCodes

  plug :assign_region

  def index(conn, %{"region_code" => region_code}) do
    %Services{ebird: %{RegionSpeciesCodes: worker}} = conn.assigns.services

    case RegionSpeciesCodes.get_codes(region_code, worker) do
      {:ok, %RegionSpeciesCodes.Response{codes: codes}} ->
        json(conn, %{birds: Bird.get_many_by_species_code(codes)})

      {:error, _} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{message: "Service Unavailable."})
    end
  end

  def assign_region(%Conn{params: %{"region_code" => region_code}} = conn, []) do
    case Region.from_code(region_code) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Unknown region."})
        |> halt()

      %Region{} = region ->
        assign(conn, :region, region)
    end
  end
end
