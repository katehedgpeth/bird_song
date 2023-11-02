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

  plug :assign_quiz
  plug :assign_bird
  plug :assign_resource, resource: :image, worker: :PhotoSearch
  plug :assign_resource, resource: :recording, worker: :Recordings

  def create(conn, %{}) do
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

  defp assign_quiz(
         %{params: %{"quiz_id" => quiz_id}, assigns: %{current_user: %{id: user_id}}} = conn,
         []
       ) do
    Quiz
    |> BirdSong.Repo.get(quiz_id)
    |> BirdSong.Repo.preload(birds: [:family, :order])
    |> case do
      %Quiz{user_id: ^user_id} = quiz ->
        assign(conn, :quiz, quiz)

      %Quiz{} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Quiz not owned by user"})
        |> halt()

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Quiz not found"})
        |> halt()
    end
  end

  defp assign_bird(%{assigns: %{quiz: %Quiz{} = quiz}} = conn, []) do
    assign(
      conn,
      :bird,
      Enum.random(quiz.birds)
    )
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
