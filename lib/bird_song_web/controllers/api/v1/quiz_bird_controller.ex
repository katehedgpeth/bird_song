defmodule BirdSongWeb.Api.V1.QuizBirdController do
  @moduledoc """
  Decides which bird to send to the frontend for the user to guess at. Currently uses
  &Enum.random/1, but in the future I would like to write a more sophisticated algorithm
  based on past responses.
  """
  use BirdSongWeb, :controller

  alias BirdSong.{
    Bird,
    Quiz,
    Services
  }

  plug BirdSongWeb.Plugs.AssignQuiz
  plug BirdSongWeb.Plugs.AssignQuizBird, assign_to: :bird

  def show(conn, %{"bird_id" => "random"}) do
    conn =
      conn
      |> assign_resource(resource: :image, worker: :PhotoSearch)
      |> assign_resource(resource: :recording, worker: :Recordings)

    _ = Map.fetch!(conn.assigns, :quiz)
    _ = Map.fetch!(conn.assigns, :bird)
    _ = Map.fetch!(conn.assigns, :recording)
    _ = Map.fetch!(conn.assigns, :image)

    %{
      quiz: %Quiz{} = quiz,
      bird: %Bird{} = bird,
      image: image,
      recording: recording
    } = conn.assigns

    json(conn, %{quiz: quiz, bird: bird, image: image, recording: recording})
  end

  defp assign_resource(
         %{assigns: %{bird: bird, services: %Services{} = services}} = conn,
         resource: resource,
         worker: worker_name
       ) do
    worker =
      services
      |> Map.fetch!(:"#{resource}s")
      |> Map.fetch!(worker_name)

    worker.module
    |> apply(:get, [bird, worker])
    |> do_assign_resource(conn, resource)
  end

  defp do_assign_resource({:ok, response}, conn, resource) do
    assign(
      conn,
      resource,
      response
      |> Map.fetch!(:"#{resource}s")
      |> Enum.random()
    )
  end
end
