defmodule BirdSongWeb.Components.Filters do
  use Phoenix.LiveComponent

  def render(%{filters: _} = assigns) do
    ~H"""
      <div id="filters">
        <.live_component
          module={__MODULE__.Region}
          id="filter-region"
          filters={@filters}
        />
        <%= filters_after_region(assigns) %>
      </div>
    """
  end

  defp filters_after_region(%{birds_by_category: _} = assigns) do
    ~H"""
      <.live_component
        module={__MODULE__.BySpecies}
        id="filter-by-species"
        birds_by_category={@birds_by_category}
        visibility={@visibility}
      />
      <button type="submit" class= "btn btn-primary block w-full" phx-click="start">
        Let's go!
      </button>
    """
  end

  defp filters_after_region(%{} = assigns) do
    assigns
    |> Map.keys()

    ~H"""
    <span></span>
    """
  end
end
