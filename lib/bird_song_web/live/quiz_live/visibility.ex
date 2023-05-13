defmodule BirdSongWeb.QuizLive.Visibility do
  import Kernel, except: [update_in: 3]

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  @type state() :: :shown | :hidden
  @type t() :: %__MODULE__{
          answer: state(),
          by_species: state(),
          filters: state(),
          image: state(),
          recording: state()
        }

  defstruct answer: :hidden,
            by_species: :hidden,
            filters: :hidden,
            image: :hidden,
            recording: :hidden

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  @spec toggle(Socket.t(), atom()) :: Socket.t()
  def toggle(%Socket{} = socket, key) do
    LiveView.assign(
      socket,
      :visibility,
      socket.assigns
      |> Map.fetch!(:visibility)
      |> Map.update!(key, &opposite/1)
    )
  end

  def visible?(%__MODULE__{} = visibility, key) do
    case Map.fetch!(visibility, key) do
      :shown -> true
      :hidden -> false
    end
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp opposite(:hidden), do: :shown
  defp opposite(:shown), do: :hidden

  defp update_in(%__MODULE__{} = struct, key, func) when is_atom(key) do
    update_in(struct, [key], func)
  end

  defp update_in(val, [], func) when is_function(func) do
    func.(val)
  end

  defp update_in(%{} = map, [key | rest], func) do
    Map.update!(map, key, &update_in(&1, rest, func))
  end

  defp update_in(keyword, [key | rest], func) when is_list(keyword) do
    Keyword.update!(keyword, key, &update_in(&1, rest, func))
  end

  defp update_in(not_map_or_keyword, [next_key | _], func) when is_function(func) do
    raise ArgumentError.exception(
            message: """
            Expected first argument to be a keyword or map containing key #{inspect(next_key)}, but got:


            #{inspect(not_map_or_keyword)}
            """
          )
  end
end
