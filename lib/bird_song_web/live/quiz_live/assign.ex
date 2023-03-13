defmodule BirdSongWeb.QuizLive.Assign do
  alias Phoenix.{LiveView, LiveView.Socket}

  defmacro __using__(_ \\ []) do
    quote do
      alias Phoenix.{LiveView, LiveView.Socket}
      import LiveView, only: [assign: 3, assign_new: 3]
      import BirdSongWeb.QuizLive.Assign
    end
  end

  def get_assign(%Socket{assigns: assigns}, key) do
    Map.fetch!(assigns, key)
  end
end
