defmodule BirdSongWeb.Components.Filters.BySpecies do
  use Phoenix.LiveComponent

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  alias BirdSong.{
    Bird,
    Quiz,
    Services,
    Services.Ebird
  }

  alias BirdSongWeb.{
    Components.ButtonGroup,
    Components.GroupButton
  }

  @type bird_state() :: %{
          bird: Bird.t(),
          selected?: boolean()
        }

  @type family_name() :: String.t()

  @type t() :: %{family_name() => [bird_state()]}

  @no_birds_error "
  Sorry, there do not appear to be any known birds in that region.
  Please choose a different or broader region.
  "

  @not_available_error "
  We're sorry, but our service is not available at the moment. Please try again later.
  "

  @assign_key :by_species

  def assign_for_region(%Socket{} = socket, %BirdSong.Region{} = region) do
    case build_for_region(region, socket.assigns[:services]) do
      {:ok, %{} = dict} ->
        assign(socket, @assign_key, dict)

      {:error, error} ->
        LiveView.put_flash(socket, :error, error_text(error))
    end
  end

  @spec build_for_region(BirdSong.Region.t(), Services.t()) ::
          t() | {:error, :no_birds_for_region} | Helpers.api_error()
  def build_for_region(%BirdSong.Region{} = region, %Services{
        ebird: %Ebird{RegionSpeciesCodes: worker}
      }) do
    case Ebird.RegionSpeciesCodes.get_codes(region, worker) do
      {:error, error} ->
        {:error, error}

      {:ok, %Ebird.RegionSpeciesCodes.Response{codes: []}} ->
        {:error, :no_codes_for_region}

      {:ok, %Ebird.RegionSpeciesCodes.Response{codes: codes}} ->
        {:ok,
         codes
         |> Bird.get_many_by_species_code()
         |> build_category_dict()}
    end
  end

  defp error_text(:no_codes_for_region), do: @no_birds_error
  defp error_text(_), do: @not_available_error

  def build_from_quiz(%Quiz{birds: birds}) do
    build_category_dict(birds)
  end

  def render(%{} = assigns) do
    ~H"""
    <div id={@id}>
      <h3>Limit to these birds (optional):</h3>

      <div class="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <%= for {category_name, birds} <- Enum.sort_by(@by_species, &elem(&1, 0)) do %>
          <.species_group
            category_name={category_name}
            birds={birds}
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp bird_filter_button(%{bird: %Bird{common_name: name}, selected?: selected?}, "" <> category) do
    %GroupButton{
      color: "primary",
      phx_click: "include?",
      phx_value: [bird: name, category: category],
      selected?: selected?,
      text: name,
      value: name
    }
  end

  defp bird_filter_buttons(%{birds: birds, category_name: category_name}) do
    assigns = %{
      birds: birds,
      category_name: category_name,
      buttons:
        birds
        |> Enum.map(&bird_filter_button(&1, category_name))
        |> Enum.sort_by(& &1.text, :desc)
    }

    ~H"""
    <div>
      <.live_component
        module={ButtonGroup}
        id={"bird-filters-" <> @category_name}
        buttons={@buttons}
      />
    </div>
    """
  end

  @spec bird_group_selection_state([bird_state()]) :: %{
          optional(true) => [bird_state()],
          optional(false) => [bird_state()]
        }
  defp bird_group_selection_state(birds) do
    Enum.group_by(birds, fn %{bird: %Bird{}, selected?: selected?} -> selected? end)
  end

  defp on_click_attrs_for_category(event, category) do
    [
      phx: [
        click: event,
        value: [category: category]
      ]
    ]
  end

  defp species_group(%{birds: _, category_name: _} = assigns) do
    ~H"""
    <div>
      <.species_filter_title birds={@birds} category_name={@category_name} />
      <.bird_filter_buttons birds={@birds} category_name={@category_name} />
    </div>
    """
  end

  defp species_filter_checkbox_attrs(%{true => _, false => _}), do: [indeterminate: true]
  defp species_filter_checkbox_attrs(%{true => _}), do: [checked: true]
  defp species_filter_checkbox_attrs(%{false => _}), do: []

  defp species_filter_checkbox(%{category_name: _name, birds: _birds} = assigns) do
    group_state = bird_group_selection_state(assigns[:birds])

    assigns =
      Map.merge(assigns, %{
        checkbox_attr: species_filter_checkbox_attrs(group_state),
        id: "species-filter-" <> assigns[:category_name],
        on_click: on_click_attrs_for_category("include?", assigns[:category_name]),
        text:
          case group_state do
            %{false => _} -> "Select all"
            %{} -> "Deselect all"
          end
      })

    ~H"""
    <div class="form-control">
      <label for={@id} class="label cursor-pointer justify-start gap-3">
        <input
          type="checkbox"
          id={@id}
          class="checkbox checkbox-xs"
          {@checkbox_attr}
          {@on_click}
        />
        <span class="label-text">
          <%= @text %>
        </span>
      </label>
    </div>

    """
  end

  defp species_filter_title(%{birds: _, category_name: _} = assigns) do
    assigns =
      Map.put(
        assigns,
        :on_click,
        on_click_attrs_for_category("toggle_visibility", assigns[:category_name])
      )

    ~H"""
    <div>
      <div class="divider my-0.5"></div>
      <div class="flex justify-between">
        <%= @category_name %>
        <%= unless length(assigns[:birds]) === 1 do %>
          <.species_filter_checkbox birds={@birds} category_name={@category_name} />
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("include?", params, socket) do
    {:noreply, update_species_categories(socket, params)}
  end

  defp build_category_dict(birds) do
    birds
    |> Enum.group_by(&Bird.family_name/1)
    |> Enum.map(&do_build_category_dict/1)
    |> Enum.into(%{})
  end

  defp do_build_category_dict({category, birds}) do
    {category, Enum.map(birds, &%{bird: &1, selected?: false})}
  end

  defp get_all_birds(%{} = by_category) do
    by_category
    |> Enum.map(&elem(&1, 1))
    |> List.flatten()
    |> Enum.map(& &1[:bird])
  end

  @spec get_selected_birds(Socket.t()) :: [Bird.t()]
  def get_selected_birds(%Socket{assigns: assigns}) do
    assigns
    |> Map.fetch!(@assign_key)
    |> Enum.map(fn {_category, birds} -> birds end)
    |> List.flatten()
    |> Enum.filter(& &1[:selected?])
    |> Enum.map(& &1[:bird])
    |> case do
      [] -> get_all_birds(assigns[@assign_key])
      [_ | _] = selected -> selected
    end
  end

  defp update_category_birds(birds, %{"bird" => name, "category" => _}) do
    Enum.map(birds, fn
      %{bird: %Bird{common_name: ^name}, selected?: _} = bird ->
        %{bird | selected?: not bird[:selected?]}

      %{bird: %Bird{}, selected?: _} = bird ->
        bird
    end)
  end

  defp update_category_birds(birds, %{"category" => _}) do
    selected? = Enum.all?(birds, & &1[:selected?])
    Enum.map(birds, &%{&1 | selected?: not selected?})
  end

  defp update_species_categories(
         %Socket{assigns: assigns} = socket,
         %{"category" => category} = params
       ) do
    LiveView.assign(
      socket,
      @assign_key,
      assigns
      |> Map.fetch!(@assign_key)
      |> Map.update!(category, &update_category_birds(&1, params))
    )
  end
end
