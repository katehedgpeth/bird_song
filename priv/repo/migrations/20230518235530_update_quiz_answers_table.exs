defmodule BirdSong.Repo.Migrations.CreateAnswersTable do
  use Ecto.Migration

  def change do
    rename table(:quiz_answers), :bird_id, to: :correct_bird_id

    alter table(:quiz_answers) do
      add :submitted_bird_id, references(:birds, on_delete: :nothing)
    end
  end
end
