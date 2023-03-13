defmodule BirdSongWeb.QuizLive.EtsTables.Tasks do
  require Logger
  alias Phoenix.LiveView.Socket
  alias BirdSong.{Bird, Services}
  alias BirdSongWeb.QuizLive.EtsTables
  import EtsTables, only: [is_ets: 1]

  @spec lookup_task(Socket.t(), reference) :: {:not_found, reference} | {:ok, any}
  def lookup_task(
        %Socket{assigns: %{ets_tables: %EtsTables{tasks: tasks_ets}}},
        ref
      )
      when is_reference(ref) do
    case :ets.lookup(tasks_ets, ref) do
      [{^ref, name: name, pid: pid}] when is_pid(pid) -> {:ok, name}
      [] -> {:not_found, ref}
    end
  end

  def remember_task(
        %Socket{assigns: %{ets_tables: %EtsTables{tasks: tasks}}} = socket,
        %Task{ref: ref, pid: pid},
        name
      )
      when is_reference(ref) and is_ets(tasks) do
    true = :ets.insert(tasks, {ref, name: name, pid: pid})
    socket
  end

  def forget_task(%Socket{} = socket, %Task{ref: ref}), do: forget_task(socket, ref)

  def forget_task(
        %Socket{assigns: %{ets_tables: %EtsTables{tasks: tasks}}} = socket,
        ref
      )
      when is_reference(ref) and is_ets(tasks) do
    :ets.delete(tasks, ref)
    socket
  end

  def kill_all_tasks(%Socket{} = socket) do
    socket
    |> get_table()
    |> :ets.tab2list()
    |> Enum.map(fn {_ref, name: name, pid: pid} when is_pid(pid) ->
      [name: name, terminated?: Task.Supervisor.terminate_child(Services.Tasks, pid)]
    end)
  end

  def get_birds(%Socket{assigns: %{birds: [%Bird{} | _] = birds}}), do: birds

  defp get_table(%Socket{assigns: %{ets_tables: %EtsTables{tasks: tasks}}}),
    do: tasks
end
