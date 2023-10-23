defmodule BirdSong.Accounts.Guardian do
  use Guardian, otp_app: :bird_song

  alias BirdSong.Accounts

  @impl Guardian
  def subject_for_token(%Accounts.User{id: user_id}, _claims) do
    {:ok, to_string(user_id)}
  end

  @impl Guardian
  def resource_from_claims(%{"sub" => id}) do
    user = Accounts.get_user!(id)
    {:ok, user}
  rescue
    Ecto.NoResultsError -> {:error, :resource_not_found}
  end
end
