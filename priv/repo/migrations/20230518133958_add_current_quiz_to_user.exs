defmodule BirdSong.Repo.Migrations.AddCurrentQuizToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :current_quiz_id, references(:quizzes, on_delete: :nothing)
    end
  end
end
