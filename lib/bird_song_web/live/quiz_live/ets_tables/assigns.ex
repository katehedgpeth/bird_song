defmodule BirdSongWeb.QuizLive.EtsTables.Assigns do
  require Logger
  alias Phoenix.LiveView.Socket

  @spec lookup_session(Socket.t()) :: {:error, {:not_found, String.t()}} | {:ok, Map.t()}
  def lookup_session(%Socket{assigns: %{session_id: nil}}) do
    {:error, {:not_found, nil}}
  end

  def lookup_session(%Socket{assigns: %{session_id: "" <> session_id}} = socket) do
    socket
    |> get_table()
    |> :ets.lookup(session_id)
    |> case do
      [{^session_id, %{} = assigns}] -> {:ok, assigns}
      [] -> {:error, {:not_found, session_id}}
    end
  end

  def remember_session(%Socket{assigns: assigns} = socket) do
    true =
      socket
      |> get_table()
      |> :ets.insert({get_session_id(socket), assigns})

    socket
  end

  def forget_session(%Socket{} = socket) do
    socket
    |> get_table()
    |> :ets.delete(get_session_id(socket))

    socket
  end

  defp get_session_id(%Socket{assigns: %{session_id: "" <> session_id}}) do
    session_id
  end

  defp get_table(%Socket{assigns: assigns}),
    do:
      assigns
      |> Map.fetch!(:ets_tables)
      |> Map.fetch!(:assigns)
end
