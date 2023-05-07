defmodule BirdSongWeb.QuizLive.New do
  require Logger
  use Phoenix.LiveView

  alias Phoenix.LiveView.Socket

  alias BirdSongWeb.{
    QuizLive,
    QuizLive.MessageHandlers,
    QuizLive.EventHandlers,
    QuizLive.Assign,
    QuizLive.EtsTables
  }

  alias BirdSong.{
    Quiz
  }

  @asset_cdn "https://cdn.download.ams.birds.cornell.edu"

  @text_input_class ~w(
    input
    input-bordered
    w-full
    disabled:text-black/40
    disabled:italic
  )

  on_mount {Assign, :assign_services}

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> Assign.assign_session_id(session)
     |> EtsTables.Assigns.lookup_session()
     |> case do
       {:ok, assigns} -> %{socket | assigns: assigns}
       {:error, {:not_found, _}} -> assign_defaults(socket, session)
     end}
  end

  def render(assigns) do
    assigns
    |> Map.fetch!(:render_listeners)
    |> Enum.each(&send(&1, {:render, assigns}))

    assigns
    |> Map.put(:inner_template, &QuizLive.HTML.NewQuiz.render/1)
    |> QuizLive.HTML.render()
  end

  def assign_defaults(%Socket{} = socket, %{} = session) do
    socket
    |> Assign.assign_session_id(session)
    |> assign(:text_input_class, @text_input_class)
    |> assign(:task_timeout, 5_000)
    |> assign(:max_api_tries, 3)
    |> QuizLive.reset_state()
    |> assign_new(:birds, fn -> [] end)
    |> assign_new(:render_listeners, fn -> [] end)
    |> assign_new(:filters, &Quiz.default_changeset/0)
    |> assign_new(:asset_cdn, fn -> @asset_cdn end)
  end

  defdelegate handle_info(message, socket), to: MessageHandlers
  defdelegate handle_event(message, payload, socket), to: EventHandlers

  if Mix.env() === :test do
    defdelegate handle_call(message, payload, socket), to: MessageHandlers
  end
end
