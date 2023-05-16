defmodule BirdSongWeb.Components.Filters.UseRecentObservations do
  use Phoenix.LiveComponent

  def render(%{} = assigns) do
    ~H"""
      <h3> <.checkbox checked={@checked} /> </h3>
    """
  end

  defp checkbox(%{} = assigns) do
    assigns = Map.put(assigns, :id, "recently-observed")

    ~H"""
      <label for={@id} class="label cursor-pointer flex justify-start items-center gap-3 inline">
        <input
          type="checkbox"
          id={@id}
          class="checkbox checkbox-xs"
          value={@checked}
          checked={@checked}
          phx-click="use_recent_observations"
        />
        Limit to recently observed species
      </label>
    """
  end
end
