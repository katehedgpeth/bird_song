defmodule BirdSongWeb.Api.QuizController do
  use BirdSongWeb, :controller

  action_fallback BirdSongWeb.FallbackController

  def create(conn, %{}) do
    json(conn, %{success: true})
  end

  def show(conn, %{}) do
    json(conn, %{success: true})
  end
end
