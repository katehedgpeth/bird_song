defmodule BirdSongWeb.QuizLive.EtsTables.Tasks do
  require Logger
  alias Phoenix.LiveView.Socket
  alias BirdSong.{Bird, Services}
  alias BirdSongWeb.QuizLive.{Caches, EtsTables}
  import EtsTables, only: [is_ets: 1]

  def start_tasks_for_all_birds(%Socket{} = socket) do
    socket
    |> EtsTables.Birds.all()
    |> Enum.reject(&Caches.has_all_data?(socket, &1))
    |> Enum.reduce(socket, &EtsTables.Tasks.start_bird_tasks(&2, &1))
  end

  def start_bird_tasks(%Socket{} = socket, %Bird{} = bird) do
    socket
    |> start_task(bird, :recordings)
  end

  def start_task(%Socket{} = socket, %Bird{} = bird, resource) when is_atom(resource) do
    remember_task(
      socket,
      Task.Supervisor.async(
        Services,
        Caches,
        :"get_#{resource}",
        [socket, bird]
      ),
      {resource, bird}
    )
  end

  def lookup_task(
        %Socket{assigns: %{ets_tables: %EtsTables{tasks: tasks_ets}}},
        ref
      )
      when is_reference(ref) do
    case :ets.lookup(tasks_ets, ref) do
      [{^ref, task}] -> {:ok, task}
      [] -> {:not_found, ref}
    end
  end

  def remember_task(
        %Socket{assigns: %{ets_tables: %EtsTables{tasks: tasks}}} = socket,
        %Task{ref: ref},
        name
      )
      when is_reference(ref) and is_ets(tasks) do
    true = :ets.insert(tasks, {ref, name})
    socket
  end

  def forget_task(
        %Socket{assigns: %{ets_tables: %EtsTables{tasks: tasks}}} = socket,
        ref
      )
      when is_reference(ref) and is_ets(tasks) do
    Logger.warn("api_calls_remaining=#{tasks |> :ets.tab2list() |> length()}")
    :ets.delete(tasks, ref)
    socket
  end
end
