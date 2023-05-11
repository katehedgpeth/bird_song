defmodule BirdSongWeb.Components.Filters.Region do
  use BirdSongWeb, :live_component

  alias Phoenix.HTML
  alias Ecto.Changeset

  alias BirdSong.{
    Quiz,
    Services.Ebird.Region
  }

  def render(%{} = assigns) do
    ~H"""
    <div id={@id}>
      <%= do_render(@filters) %>
    </div>
    """
  end

  defp do_render(%Quiz{region: "" <> region}) do
    region
    |> Region.from_code!()
    |> region_with_change_button()
  end

  defp do_render(%Changeset{} = filters) do
    region_form(%{filters: filters})
  end

  def region_with_change_button(%Region{} = assigns) do
    ~H"""
    <div class="flex">
      <div>Region: <%= @name %></div>
      <button type="button" phx-click="change_region">
        Change region
      </button>
    </div>
    """
  end

  def region_form(%{filters: %Changeset{}} = assigns) do
    ~H"""
      <.form
        for={@filters}
        let={f}
        id="filter-region-form"
        phx-submit="set_region"
      >

      <div>
        <.region_label field={f[:region]} />
        <div class="flex">
          <.region_input field={f[:region]} />
          <.region_submit />
        </div>
      </div>
      </.form>
    """
  end

  defp region_label(%{field: %HTML.FormField{}} = assigns) do
    ~H"""
    <label for={@field.id}>
      <span>
        Region
        <span class="italic">
          (can be city, state, or country)
        </span>
      </span>
    </label>
    """
  end

  defp region_input(%{field: %HTML.FormField{}} = assigns) do
    ~H"""
      <input
        type="text"
        id={@field.id}
        name={@field.name}
        value={@field.value}
        phx-debounce="blur"
        class={~w(
          input
          input-bordered
          w-full
          disabled:text-black/40
          disabled:italic
        )}
      />
    """
  end

  defp region_submit(%{} = assigns) do
    ~H"""
      <button type="submit" class="btn" id="region-btn">
        Set Region
      </button>
    """
  end
end
