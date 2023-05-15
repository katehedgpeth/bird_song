defmodule BirdSongWeb.Components.Filters.ByFamily.Assigns do
  alias Phoenix.LiveView

  alias BirdSongWeb.Components.{
    Filters,
    Filters.ByFamily
  }

  alias BirdSong.{
    Bird,
    Family,
    Quiz,
    Services,
    Services.Ebird
  }

  @assign_key :by_family

  @no_birds_error "
  Sorry, there do not appear to be any known birds in that region.
  Please choose a different or broader region.
  "

  @not_available_error "
  We're sorry, but our service is not available at the moment. Please try again later.
  "

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  @spec build_selected(Filters.t(), Quiz.t()) :: ByFamily.t() | {:error, String.t()}
  def build_selected(
        %{services: _} = assigns,
        %Quiz{} = quiz
      ) do
    assigns[@assign_key]
    |> build_for_region(assigns.services, quiz)
    |> case do
      {:error, error} ->
        {:error, error_text(error)}

      {:ok, %{} = dict} ->
        update_selected(dict, quiz)
    end
  end

  def handle_event("include?", params, socket) do
    {:noreply,
     LiveView.assign(
       socket,
       @assign_key,
       update_selected(socket.assigns[@assign_key], params)
     )}
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
    |> Enum.group_by(&Bird.family_name/1)
    |> Enum.map(&do_build_family_dict/1)
    |> Enum.into(%{})
  end

  defp do_build_family_dict({family, birds}) do
    {family, Enum.map(birds, &%{bird: &1, selected?: false})}
  end

  @spec build_for_region(ByFamily.t() | nil, Services.t(), Quiz.t()) ::
          {:ok, ByFamily.t()} | {:error, :no_birds_for_region} | Helpers.api_error()
  defp build_for_region(%{} = existing_dict, %Services{}, %Quiz{}) do
    {:ok, existing_dict}
  end

  defp build_for_region(nil, %Services{} = services, %Quiz{region_code: region_code}) do
    region_code
    |> BirdSong.Region.from_code!()
    |> Ebird.RegionSpeciesCodes.get_codes(services.ebird[:RegionSpeciesCodes])
    |> case do
      {:error, error} ->
        {:error, error}

      {:ok, %Ebird.RegionSpeciesCodes.Response{codes: []}} ->
        {:error, :no_codes_for_region}

      {:ok, %Ebird.RegionSpeciesCodes.Response{codes: codes}} ->
        {:ok,
         codes
         |> Bird.get_many_by_species_code()
         |> build_family_dict()}
    end
  end

  def build_from_quiz(%Quiz{} = quiz) do
    quiz.region_code
    |> BirdSong.Region.from_code!()
    |> build_family_dict()
    |> update_selected(quiz)
  end

  defp deselect_all_in_family({family_name, birds}) do
    {family_name, Enum.map(birds, &%{&1 | selected?: false})}
  end

  defp error_text(:no_codes_for_region), do: @no_birds_error
  defp error_text(_), do: @not_available_error

  defp get_all_birds(%{} = by_family) do
    by_family
    |> Enum.map(&elem(&1, 1))
    |> List.flatten()
    |> Enum.map(& &1[:bird])
  end

  @spec get_selected_birds(Map.t()) :: [Bird.t()]
  def get_selected_birds(%{} = assigns) do
    assigns
    |> Map.fetch!(@assign_key)
    |> Enum.map(fn {_family, birds} -> birds end)
    |> List.flatten()
    |> Enum.filter(& &1[:selected?])
    |> Enum.map(& &1[:bird])
    |> case do
      [] -> get_all_birds(assigns[@assign_key])
      [_ | _] = selected -> selected
    end
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

  defp update_selected(%{} = by_family, %Quiz{birds: []}) do
    Map.new(by_family, &deselect_all_in_family/1)
  end

  defp update_selected(%{} = by_family, %Quiz{} = quiz) do
    quiz.birds
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
