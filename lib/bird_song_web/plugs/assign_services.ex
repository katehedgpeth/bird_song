defmodule BirdSongWeb.Plugs.AssignServices do
  alias Plug.Conn
  alias BirdSong.Services

  @behaviour Plug

  @impl Plug
  def init([]), do: []

  @impl Plug
  def call(%Conn{params: %{"services" => name}} = conn, []) do
    try do
      Conn.assign(
        conn,
        :services,
        name
        |> String.to_existing_atom()
        |> Services.all()
      )
    rescue
      ArgumentError ->
        # String.to_existing_atom/1 threw an error
        conn
        |> Conn.put_status(:bad_request)
        |> Phoenix.Controller.json(%{})
        |> Conn.halt()
    end
  end

  def call(conn, []) do
    Conn.assign(conn, :services, Services.all())
  end
end
