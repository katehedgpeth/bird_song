defmodule BirdSong.Accounts.Pipeline do
  use Guardian.Plug.Pipeline,
    otp_app: :bird_song,
    error_handler: BirdSong.Accounts.GuardianErrorHandler,
    module: BirdSong.Accounts.Guardian

  # If there is a session token, restrict it to an access token and validate it
  plug Guardian.Plug.VerifySession, claims: %{"typ" => "access"}

  # If there is an authorization header, restrict it to an access token and validate it
  plug Guardian.Plug.VerifyHeader, claims: %{"typ" => "access"}
end
