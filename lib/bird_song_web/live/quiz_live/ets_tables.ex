defmodule BirdSongWeb.QuizLive.EtsTables do
  use BirdSongWeb.QuizLive.Assign
  use BirdSong.GenServer, name: __MODULE__, keep_name_opt?: true
  alias Phoenix.LiveView.Socket

  defstruct [:birds, :assigns]

  @type t() :: %__MODULE__{
          assigns: :ets.table()
        }

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  def assign_tables(%Socket{} = socket), do: assign_tables(socket, __MODULE__)

  @spec assign_tables(Socket.t(), atom() | pid()) :: Socket.t()
  def assign_tables(%Socket{assigns: %{ets_tables: tables}} = socket, _server) do
    # this case clause is here to ensure that the assign has the correct format
    case tables do
      %__MODULE__{} -> socket
    end
  end

  def assign_tables(%Socket{assigns: %{}} = socket, server) do
    Phoenix.LiveView.assign_new(socket, :ets_tables, fn -> ensure_started(server) end)
  end

  def get_ets_server_name(%{"ets_server" => "" <> name}), do: String.to_existing_atom(name)
  def get_ets_server_name(%{}), do: __MODULE__

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  def handle_call(:get_tables, _from, %__MODULE__{} = state) do
    {:reply, state, state}
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  @spec build_state(Keyword.t()) :: t()
  defp build_state(opts) do
    {name, opts} = Keyword.pop!(opts, :name)

    opts
    |> Keyword.put_new_lazy(:assigns, fn ->
      name
      |> Module.concat(Assigns)
      |> :ets.new([:public])
    end)
    |> __struct__()
  end

  @spec ensure_started(atom() | pid()) :: t()
  defp ensure_started(pid) when is_pid(pid) do
    GenServer.call(pid, :get_tables)
  end

  defp ensure_started(server) when is_atom(server) do
    BirdSong.Services.GenServers
    |> DynamicSupervisor.start_child({__MODULE__, name: server})
    |> case do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
    |> ensure_started()
  end
end
