defmodule BirdSong.Services do
  def call_service({module, func, args}) do
    Task.Supervisor.async_nolink(__MODULE__, module, func, args)
  end
end
