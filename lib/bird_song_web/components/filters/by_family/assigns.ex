defmodule BirdSongWeb.Components.Filters.ByFamily.Assigns do
  alias Phoenix.LiveView

  alias BirdSongWeb.Components.{
    Filters.ByFamily
  }

  alias BirdSong.{
    Bird,
    Family,
    Quiz
  }

  @type event_params() :: %{
          required(String.t()) => Family.name(),
          optional(String.t()) => Bird.common_name()
        }

  @type bird_state() :: %{
          bird: Bird.t(),
          selected?: boolean(),
          disabled?: boolean()
        }

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  @spec build_dict([ByFamily.bird_state()], [Bird.t()]) :: ByFamily.t()
  def build_dict([%{bird: _} | _] = all, selected) when is_list(selected) do
    all
    |> build_family_dict()
    |> update_selected(selected)
  end

  def handle_event("include?", params, socket) do
    {:noreply,
     LiveView.assign(
       socket,
       :by_family,
       update_selected(socket.assigns.by_family, params)
     )}
  end

  @spec get_selected_birds(ByFamily.t()) :: [Bird.t()]
  def get_selected_birds(%{} = by_family) do
    by_family
    |> flatten_dict()
    |> Enum.reject(& &1.disabled?)
    |> Enum.filter(& &1.selected?)
    |> Enum.map(& &1.bird)
  end

  def get_all_birds(%{} = by_family) do
    by_family
    |> flatten_dict()
    |> Enum.map(& &1.bird)
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp bird_to_params(%Bird{common_name: common_name, family: %Family{common_name: family_name}}) do
    %{"family" => family_name, "bird" => common_name}
  end

  defp build_family_dict(birds) do
    birds
    |> Enum.group_by(&Bird.family_name(&1.bird))
    |> Enum.into(%{})
  end

  def build_from_quiz(%Quiz{} = quiz) do
    quiz.region_code
    |> BirdSong.Region.from_code!()
    |> build_family_dict()
    |> update_selected(quiz.birds)
  end

  defp deselect_all_in_family({family_name, birds}) do
    {family_name, Enum.map(birds, &%{&1 | selected?: false})}
  end

  defp flatten_dict(%{} = dict) do
    dict
    |> Enum.map(&get_family_birds/1)
    |> List.flatten()
  end

  defp get_family_birds({_family, [%{bird: _} | _] = birds}) do
    birds
  end

  defp update_family_birds(birds, %{"bird" => name, "family" => _}) do
    Enum.map(birds, fn
      %{bird: %Bird{common_name: ^name}, selected?: _} = bird ->
        %{bird | selected?: not bird[:selected?]}

      %{bird: %Bird{}, selected?: _} = bird ->
        bird
    end)
  end

  defp update_family_birds(birds, %{"family" => _}) do
    selected? = Enum.all?(birds, & &1[:selected?])
    Enum.map(birds, &%{&1 | selected?: not selected?})
  end

  @spec update_selected(ByFamily.t(), [Bird.t()] | event_params()) :: ByFamily.t()
  defp update_selected(%{} = by_family, []) do
    Map.new(by_family, &deselect_all_in_family/1)
  end

  defp update_selected(%{} = by_family, [%Bird{} | _] = birds) do
    birds
    |> Enum.map(&bird_to_params/1)
    |> Enum.reduce(by_family, &update_selected(&2, &1))
  end

  defp update_selected(
         %{} = by_family,
         %{"family" => family} = params
       ) do
    Map.update!(by_family, family, &update_family_birds(&1, params))
  end
end
