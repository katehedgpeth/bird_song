ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(BirdSong.Repo, :manual)
ExUnit.after_suite(fn %{} -> File.rm_rf("tmp") end)
