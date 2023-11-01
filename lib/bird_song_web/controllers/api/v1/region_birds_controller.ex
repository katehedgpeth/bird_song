defmodule BirdSongWeb.Api.V1.RegionBirdsController do
  use BirdSongWeb, :controller

  alias Plug.Conn

  alias BirdSong.{Bird, Services, Region}
  alias BirdSong.Services.Ebird.RegionSpeciesCodes

  plug :assign_worker
  plug :assign_region

  def index(conn, %{"region_code" => region_code}) do
    case RegionSpeciesCodes.get_codes(region_code, conn.assigns.worker) do
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

  def assign_worker(%Conn{params: %{"services" => name}} = conn, []) do
    case get_services_name(name) do
      {:ok, instance_name} ->
        instance_name
        |> Services.all()
        |> do_assign_worker(conn)

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{})
        |> halt()
    end
  end

  def assign_worker(conn, []) do
    Services.all()
    |> do_assign_worker(conn)
  end

  defp do_assign_worker(%Services{ebird: %{RegionSpeciesCodes: worker}}, conn) do
    assign(conn, :worker, worker)
  end

  defp get_services_name(name) do
    try do
      {:ok, String.to_existing_atom(name)}
    rescue
      ArgumentError ->
        :error
    end
  end
end
