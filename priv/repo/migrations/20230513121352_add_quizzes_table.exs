defmodule BirdSong.Repo.Migrations.AddQuizzesTable do
  use Ecto.Migration

  def change() do
    drop_if_exists table(:quizzes)
    drop_if_exists table(:birds_quizzes)
    create_quizzes()
    create_birds_quizzes_join_table()
  end

  def create_quizzes() do
    create table(:quizzes) do
      add :correct_answers, :integer, default: 0
      add :incorrect_answers, :integer, default: 0
      add :quiz_length, :integer, default: 10
      add :region_code, :string
      add :session_id, :string

      timestamps()
    end

    create index(:quizzes, :region_code)
    create index(:quizzes, :session_id)
  end

  def create_birds_quizzes_join_table() do
    create table(:birds_quizzes) do
      add :bird_id, references(:birds, on_delete: :delete_all)
      add :quiz_id, references(:quizzes, on_delete: :delete_all)
    end

    create index(:birds_quizzes, :bird_id)
    create index(:birds_quizzes, :quiz_id)
  end
end
