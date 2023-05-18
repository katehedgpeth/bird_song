defmodule BirdSong.Repo.Migrations.CreateUniqueIndexBirdsQuizzes do
  use Ecto.Migration

  def change do
    create unique_index(:birds_quizzes, [:bird_id, :quiz_id])
  end
end
