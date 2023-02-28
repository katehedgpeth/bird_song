defmodule BirdSongWeb.QuizLive.EtsTables.Birds do
  alias Phoenix.{LiveView, LiveView.Socket}
  alias BirdSongWeb.QuizLive.EtsTables
  alias BirdSong.Services.Ebird
  alias BirdSong.Bird

  import EtsTables, only: [is_ets: 1]

  @spec update_bird_count(Socket.t()) :: Socket.t()
  def update_bird_count(%Socket{} = socket) do
    LiveView.assign(
      socket,
      :bird_count,
      get_bird_count(socket)
    )
  end

  def get_bird_count(%Socket{} = socket) do
    socket
    |> get_table()
    |> :ets.tab2list()
    |> Kernel.length()
  end

  @spec all(Socket.t() | :ets.table()) :: [Bird.t()]
  def all(%Socket{} = socket) do
    socket
    |> get_table()
    |> all()
  end

  def all(table) when is_ets(table) do
    table
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
  end

  @spec save_bird(Socket.t(), Ebird.Observation.t()) ::
          {:ok, Bird.t()} | {:error, {:already_exists, Bird.t()}}
  def save_bird(
        %Socket{} = socket,
        %Ebird.Observation{sci_name: sci_name} = obs
      ) do
    bird = Bird.new(obs)

    socket
    |> get_table()
    |> :ets.insert_new({sci_name, bird})
    |> case do
      true -> {:ok, bird}
      false -> {:error, {:already_exists, bird}}
    end
  end

  @spec lookup_bird(:ets.table() | Socket.t(), String.t()) :: {:ok, Bird.t()} | :not_found
  def lookup_bird(%Socket{} = socket, "" <> sci_name) do
    socket
    |> get_table()
    |> lookup_bird(sci_name)
  end

  def lookup_bird(birds_ets, "" <> sci_name) when is_ets(birds_ets) do
    case :ets.lookup(birds_ets, sci_name) do
      [{^sci_name, %Bird{} = bird}] -> {:ok, bird}
      [] -> :not_found
    end
  end

  @spec update_bird(Socket.t(), Bird.t()) :: :ok
  def update_bird(
        %Socket{} = socket,
        %Bird{sci_name: sci_name} = bird
      ) do
    socket
    |> get_table()
    |> :ets.insert({sci_name, bird})
    |> case do
      true -> :ok
    end
  end

  defp get_table(%Socket{assigns: %{ets_tables: %EtsTables{birds: birds}}}) when is_ets(birds),
    do: birds
end
