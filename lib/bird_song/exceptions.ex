defmodule BirdSong.MissingEnvironmentVariableError do
  use BirdSong.CustomError, [:name]

  def message_text(%__MODULE__{name: name}) do
    "missing environment variable: " <> name
  end
end
