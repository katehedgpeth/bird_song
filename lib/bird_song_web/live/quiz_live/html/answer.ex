defmodule BirdSongWeb.QuizLive.HTML.Answer do
  use Phoenix.LiveComponent

  alias BirdSong.{
    Bird,
    Quiz,
    Quiz.Answer
  }

  alias BirdSongWeb.{
    Components.ButtonGroup,
    Components.GroupButton,
    QuizLive.Current
  }

  def render(%{} = assigns) do
    ~H"""
    <div class={["p-10", "w-full", answer_section_bg_class(@current)]}>
      <.inner_content current={@current} quiz={@quiz} rendering_module={@rendering_module} />
    </div>
    """
  end

  defp answer(%{current: %Current{answer: %Answer{}}} = assigns) do
    ~H"""
      <div class="text-center">
        <.correct_or_incorrect {assigns} />
        <.live_component module={@rendering_module} id="also-audible" recording={@current.recording} />
        <.next_button />
      </div>
    """
  end

  defp correct_or_incorrect(
         %{
           current: %{
             answer: %Quiz.Answer{correct?: true}
           }
         } = assigns
       ) do
    ~H"""
      <h2 class="font-bold">Correct!</h2>
      <%= @current.bird.common_name %>
    """
  end

  defp correct_or_incorrect(
         %{
           current: %Current{
             answer: %Quiz.Answer{correct?: false}
           }
         } = assigns
       ) do
    ~H"""
      <p>Your guess: <%= @current.answer.submitted_bird.common_name %></p>
      <h2>Correct answer: <span class="font-bold"><%= @current.bird.common_name %></span></h2>
    """
  end

  defp answer_section_bg_class(%Current{answer: nil}), do: "bg-slate-100"
  defp answer_section_bg_class(%Current{answer: %Answer{correct?: true}}), do: "bg-success"
  defp answer_section_bg_class(%Current{answer: %Answer{correct?: false}}), do: "bg-error"

  defp inner_content(%{current: %Current{answer: nil}} = assigns) do
    ~H"""
      <.possible_birds quiz={@quiz} />
    """
  end

  defp inner_content(%{current: %Current{answer: %Answer{}}} = assigns) do
    ~H"""
      <.answer current={@current} rendering_module={@rendering_module} />
    """
  end

  defp next_button(%{} = assigns) do
    ~H"""
      <button phx-click="next" class="btn btn-outline">Next</button>
    """
  end

  defp possible_birds(%{quiz: %Quiz{}} = assigns) do
    ~H"""
      <div>
        <h3>Possible Birds:</h3>
        <.possible_bird_buttons birds={@quiz.birds} />
      </div>
    """
  end

  defp possible_bird_buttons(%{birds: birds}) do
    assigns = %{
      buttons: Enum.map(birds, &possible_bird_button/1)
    }

    ~H"""
      <.live_component
        module={ButtonGroup}
        id="possible-birds"
        buttons={@buttons}
      />
    """
  end

  defp possible_bird_button(%Bird{common_name: name, species_code: code, id: id}) do
    %GroupButton{
      text: name,
      value: code,
      phx_click: "submit_answer",
      phx_value: [bird: id]
    }
  end
end
