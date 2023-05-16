defmodule BirdSong.Repo.Migrations.AddUseRecentObsToQuiz do
  use Ecto.Migration

  def change do
    alter table(:quizzes) do
      add :use_recent_observations?, :boolean, default: true
    end
  end
end
