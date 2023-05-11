defmodule BirdSongWeb.QuizLive.Visibility do
  import Kernel, except: [update_in: 3]

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  @type state() :: :shown | :hidden
  @type t() :: %__MODULE__{
          answer: state(),
          image: state(),
          recording: state(),
          category_filters: %{
            String.t() => state()
          }
        }

  defstruct answer: :hidden,
            image: :hidden,
            recording: :hidden,
            category_filters: %{}

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  @spec reset_category_filters(Socket.t()) :: Socket.t()
  def reset_category_filters(%Socket{} = socket) do
    %{
      birds_by_category: %{} = by_category,
      visibility: %__MODULE__{} = state
    } = Map.take(socket.assigns, [:visibility, :birds_by_category])

    LiveView.assign(
      socket,
      :visibility,
      Enum.reduce(by_category, state, &add_category/2)
    )
  end

  @spec toggle(Socket.t(), atom() | list(atom())) :: Socket.t()
  def toggle(%Socket{} = socket, key_or_keys) do
    LiveView.assign(
      socket,
      :visibility,
      socket.assigns
      |> Map.fetch!(:visibility)
      |> update_in(key_or_keys, &opposite/1)
    )
  end

  def visible?(
        %__MODULE__{category_filters: filters},
        :category_filters,
        "" <> category_name
      ) do
    do_visible?(filters, category_name)
  end

  def visible?(%__MODULE__{} = visibility, key) do
    do_visible?(visibility, key)
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp add_category({name, _}, %__MODULE__{} = visibility) do
    Map.update!(visibility, :category_filters, &Map.put(&1, name, :hidden))
  end

  defp do_visible?(%{} = state, key) do
    case Map.fetch!(state, key) do
      :shown -> true
      :hidden -> false
    end
  end

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
