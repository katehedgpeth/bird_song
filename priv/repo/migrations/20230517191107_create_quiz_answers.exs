defmodule BirdSong.Repo.Migrations.CreateQuizAnswers do
  use Ecto.Migration

  def change do
    create table(:quiz_answers) do
      add :correct?, :boolean, default: false, null: false
      add :quiz_id, references(:quizzes, on_delete: :nothing)
      add :bird_id, references(:birds, on_delete: :nothing)

      timestamps()
    end

    create index(:quiz_answers, [:quiz_id])
    create index(:quiz_answers, [:bird_id])

    alter table(:quizzes) do
      add :user_id, references(:users, on_delete: :nothing)
      remove :session_id
    end
  end
end
