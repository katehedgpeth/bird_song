defmodule BirdSongWeb.Components.Stats do
  use Phoenix.LiveComponent

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  alias BirdSong.{
    Quiz.Answer,
    Stats,
    Stats.Counts
  }

  alias BirdSongWeb.{
    QuizLive.Assign
  }

  def on_mount(:get, _params_or_not_mounted_at_router, %{}, %Socket{} = socket) do
    {:cont, LiveView.assign(socket, :stats, Stats.get_counts(socket.assigns.user.id))}
  end

  def update_counts(%Assign{} = assigns, %Answer{} = answer) do
    %{
      assigns
      | stats: Stats.update_struct(assigns.stats, &do_update_counts(&1, &2, answer))
    }
  end

  defp do_update_counts(key, %Stats{} = stats, %Answer{} = answer) do
    Map.update!(stats, key, &Counts.update_counts(&1, answer))
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div>
      <h2>My Stats</h2>
      <div>
        <div>
          Current set: <.pct data={@stats.current_quiz} />
        </div>
        <div>
          Today: <.pct data={@stats.today} />
        </div>
        <div>
          All time: <.pct data={@stats.all_time} />
        </div>
      </div>
    </div>
    """
  end

  defp pct(%{data: %Counts{total: 0}} = assigns) do
    ~H"""
      <span>(no data)</span>
    """
  end

  defp pct(%{} = assigns) do
    ~H"""
    <span>
      <%= @data.correct %> / <%= @data.total %>
      (<%= Counts.calculate(@data) %>%)
    </span>
    """
  end
end
