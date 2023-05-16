defmodule BirdSongWeb.QuizLive.HTML.Question do
  use Phoenix.LiveComponent
  alias BirdSongWeb.QuizLive.Assign
  alias BirdSongWeb.QuizLive.Current
  alias BirdSongWeb.QuizLive.Visibility

  alias BirdSongWeb.{
    Components.ButtonGroup,
    Components.GroupButton,
    QuizLive
  }

  alias BirdSong.{
    Bird,
    Quiz,
    Services.Flickr,
    Services.MacaulayLibrary
  }

  def render(%{quiz: %Quiz{}} = assigns) do
    assigns = Assign.assigns_to_struct(assigns)

    ~H"""
      <div>
        <%= QuizLive.HTML.page_title("What bird do you hear?") %>
        <div class="flex gap-10 flex-col">
          <div class="flex flex-wrap justify-center gap-5">
            <button phx-click="next" class="btn btn-secondary">Skip to next bird</button>
            <.play_audio current={@current} asset_cdn={@asset_cdn} />
            <button phx-click="change" phx-value-element="recording" class="btn btn-outline">Change recording</button>
          </div>
          <div class="bg-slate-100 p-10 w-full">
            <.show_answer visibility={@visibility} current={@current} />
          </div>
            <.show_possible_birds quiz={@quiz} />
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <.show_image visibility={@visibility} current={@current} />
            <.show_recording_details
              visibility={@visibility}
              asset_cdn={@asset_cdn} current={@current}
            />
          </div>

          <.filters visibility={@visibility} socket={@socket} services={@services} />

        </div>
      </div>
    """
  end

  def render(%{} = assigns) do
    ~H"""
    <div>Loading...</div>
    """
  end

  ####################################################
  ####################################################
  ##
  ##  PRIVATE METHODS
  ##
  ####################################################

  defp image(%{visibility: %Visibility{image: :hidden}} = assigns) do
    ~H"""
    <.toggle_button element="image", text="Image" />
    """
  end

  defp image(%{
         visibility: %Visibility{image: :shown},
         current: %Current{image: image}
       }) do
    assigns = %{
      btn_class: "btn btn-outline",
      src:
        image
        |> rendering_module()
        |> apply(:src, [image])
    }

    ~H"""
      <img src={@src} class="block" />
      <div>
        <%= for {action, text} <- [{"change", "Change"}, {"toggle_visibility", "Hide"}] do %>
          <button
            class={@btn_class}
            phx-click={action}
            phx-value-element="image">
            <%= text %> image
          </button>
        <% end %>
      </div>

    """
  end

  defp audio_src(recording, asset_cdn) do
    recording
    |> rendering_module()
    |> apply(:audio_src, [recording, asset_cdn])
  end

  defp filters(assigns) do
    ~H"""
    <span></span>
    """
  end

  defp play_audio(%{current: %Current{}, asset_cdn: _} = assigns) do
    ~H"""
      <audio autoplay={true} src={audio_src(@current.recording, @asset_cdn)} controls={true} />
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

  defp possible_bird_button(%Bird{common_name: name, species_code: code}) do
    %GroupButton{
      text: name,
      value: code,
      phx_click: "",
      phx_value: [bird: name]
    }
  end

  defp rendering_module(%MacaulayLibrary.Recording{}), do: QuizLive.HTML.Recordings.Ebird
  defp rendering_module(%Flickr.Photo{}), do: QuizLive.HTML.Images.Flickr

  defp show_answer(%{
         visibility: %Visibility{answer: :shown},
         current: %{
           bird: %Bird{common_name: name},
           recording: recording,
           image: _
         }
       }) do
    assigns = %{
      name: name,
      recording: recording
    }

    ~H"""
    <div class="text-center">
      <%= @name %>
      <.live_component module={rendering_module(@recording)} id="also-audible" recording={@recording} />
    </div>
    """
  end

  defp show_answer(%{visibility: %Visibility{answer: :hidden}}),
    do: toggle_button(%{element: "answer", text: "Answer"})

  defp toggle_button(%{element: _, text: _} = assigns) do
    ~H"""
    <button
      class="btn btn-outline mx-auto block"
      phx-click="toggle_visibility"
      phx-value-element={@element}
    >
      Show <%= @text %>
    </button>
    """
  end

  defp show_image(assigns) do
    ~H"""
    <div class="flex-none">
      <%= image(assigns) %>
    </div>
    """
  end

  defp show_possible_birds(%{quiz: %Quiz{}} = assigns) do
    ~H"""
      <div>
        <h3>Possible Birds:</h3>
        <.possible_bird_buttons birds={@quiz.birds} />
      </div>
    """
  end

  defp show_recording_details(%{
         visibility: %Visibility{recording: :shown},
         current: %{recording: %{} = recording},
         asset_cdn: "" <> asset_cdn
       }) do
    assigns = %{
      asset_cdn: asset_cdn,
      recording: recording
    }

    ~H"""
      <.live_component
        module={rendering_module(@recording)}
        id="recording_details"
        {assigns}
      />
    """
  end

  defp show_recording_details(%{visibility: %Visibility{recording: :hidden}}) do
    toggle_button(%{element: "recording", text: "Recording Details"})
  end
end
