defmodule BirdSongWeb.LiveCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      use BirdSongWeb.ConnCase
      import Phoenix.LiveViewTest
    end
  end
end
