defmodule BirdSongWeb.Components.Filters.BySpeciesTest do
  use BirdSongWeb.LiveCase, async: true
  use BirdSong.MockDataAttributes
  alias BirdSongWeb.Components.Filters.BySpecies

  describe "bird filter buttons" do
    test "unselected" do
      html =
        render_component(
          BySpecies,
          id: "by_species",
          by_species: %{
            "Backyard Birds" => [
              %{selected?: false, bird: @carolina_wren},
              %{selected?: false, bird: @eastern_bluebird}
            ]
          }
        )

      assert [bluebird, wren] = Floki.find(html, ".btn")

      for {html, name} <- [
            {bluebird, @eastern_bluebird.common_name},
            {wren, @carolina_wren.common_name}
          ] do
        assert Floki.text(html) =~ ~r(\s+#{name}\s+)
        assert Floki.attribute(html, "aria-checked") === []
        [classes] = Floki.attribute(html, "class")
        assert classes =~ "btn-outline"
      end
    end

    test "selected" do
      html =
        render_component(
          BySpecies,
          id: "by_species",
          by_species: %{
            "Backyard Birds" => [
              %{selected?: true, bird: @carolina_wren},
              %{selected?: false, bird: @eastern_bluebird}
            ]
          }
        )

      assert [bluebird, wren] = Floki.find(html, ".btn")

      for {html, name, aria_checked} <- [
            {bluebird, @eastern_bluebird.common_name, :error},
            {wren, @carolina_wren.common_name, {:ok, "aria-checked"}}
          ] do
        assert Floki.text(html) =~ ~r(\s+#{name}\s+)
        assert {"div", _, [{"button", attrs, _}]} = html
        attrs = Map.new(attrs)

        case name do
          "Eastern Bluebird" -> :ok
          "Carolina Wren" -> assert %{"aria-checked" => "aria-checked"} = attrs
        end

        assert Map.fetch(attrs, "aria-checked") === aria_checked
      end

      [bluebird_class, wren_class] = Floki.attribute([bluebird, wren], "class")
      assert bluebird_class =~ "btn-outline"
      refute wren_class =~ "btn-outline"
    end
  end
end
