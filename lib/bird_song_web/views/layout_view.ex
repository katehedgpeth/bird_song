defmodule BirdSongWeb.LayoutView do
  use BirdSongWeb, :view

  # Phoenix LiveDashboard is available only in development by default,
  # so we instruct Elixir to not warn if the dashboard route is missing.
  @compile {:no_warn_undefined, {Routes, :live_dashboard_path, 2}}

  def render_flash(conn, type) do
    case get_flash(conn, type) do
      nil -> ""
      flash -> content_tag(:p, [flash], class: ["alert", flash_error_class(type)], role: "alert")
    end
  end

  defp flash_error_class(:info), do: "alert-info"
  defp flash_error_class(:error), do: "alert-danger"
end
