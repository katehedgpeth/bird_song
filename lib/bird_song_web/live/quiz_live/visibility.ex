defmodule BirdSongWeb.QuizLive.Visibility do
  import Kernel, except: [update_in: 3]

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  @type state() :: :shown | :hidden

  @type by_family() :: %{
          required(String.t()) => state()
        }
  @type t() :: %__MODULE__{
          answer: state(),
          by_family: state(),
          filters: state(),
          image: state(),
          recording: state(),
          families: by_family()
        }

  defstruct answer: :hidden,
            by_family: :hidden,
            families: %{},
            filters: :hidden,
            image: :hidden,
            recording: :hidden

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  @spec toggle(Socket.t(), atom(), String.t() | nil) :: Socket.t()
  def toggle(%Socket{} = socket, key, family \\ nil) do
    LiveView.assign(
      socket,
      :visibility,
      socket.assigns
      |> Map.fetch!(:visibility)
      |> do_toggle(key, family)
    )
  end

  defp do_toggle(%__MODULE__{} = state, key, nil) do
    Map.update!(state, key, &opposite/1)
  end

  defp do_toggle(%__MODULE__{} = state, :families, "" <> family) do
    %{state | families: Map.update!(state.families, family, &opposite/1)}
  end

  def visible?(%__MODULE__{} = visibility, key) do
    case Map.fetch!(visibility, key) do
      :shown -> true
      :hidden -> false
    end
  end

  def add_families(%__MODULE__{} = state, families) do
    Enum.reduce(families, state, &add_family/2)
  end

  defp add_family("" <> family_name, %__MODULE__{} = state) do
    Map.update!(state, :families, &Map.put_new(&1, family_name, :hidden))
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp opposite(:hidden), do: :shown
  defp opposite(:shown), do: :hidden
end
