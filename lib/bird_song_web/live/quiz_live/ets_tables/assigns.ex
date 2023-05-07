defmodule BirdSongWeb.QuizLive.EtsTables.Assigns do
  require Logger
  alias Phoenix.LiveView.Socket

  alias BirdSongWeb.QuizLive.EtsTables

  @spec lookup_session(Socket.t()) :: {:error, {:not_found, String.t()}} | {:ok, Map.t()}
  def lookup_session(%Socket{assigns: %{session_id: nil}}) do
    {:error, {:not_found, nil}}
  end

  def lookup_session(%Socket{assigns: assigns}) do
    %{session_id: "" <> session_id} = Map.take(assigns, [:session_id])

    get_table()
    |> :ets.lookup(session_id)
    |> case do
      [{^session_id, %{} = assigns}] -> {:ok, assigns}
      [] -> {:error, {:not_found, session_id}}
    end
  end

  def remember_session(%Socket{assigns: assigns} = socket) do
    true =
      get_table()
      |> :ets.insert({get_session_id(socket), assigns})

    socket
  end

  def forget_session(%Socket{} = socket) do
    get_table()
    |> :ets.delete(get_session_id(socket))

    socket
  end

  defp get_session_id(%Socket{assigns: %{session_id: "" <> session_id}}) do
    session_id
  end

  defp get_table() do
    EtsTables.get_tables().assigns
  end
end
