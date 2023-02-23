defmodule BirdSong.TestHelpers do
  def update_env(service, key, new_value) do
    old_env = Application.fetch_env!(:bird_song, service)
    func = if Keyword.has_key?(old_env, key), do: :replace!, else: :put

    Application.put_env(
      :ebird,
      service,
      apply(Keyword, func, [old_env, key, new_value])
    )
  end
end
