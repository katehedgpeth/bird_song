defmodule BirdSong.Services.Supervisor.NotStartedError do
  @struct_keys [:module, :service, :supervisor]
  @enforce_keys @struct_keys
  defexception @struct_keys

  def message(%__MODULE__{module: module, service: service, supervisor: supervisor}) do
    """

    Supervisor has not been started!

    service module: #{inspect(module)}
    service instance name: #{inspect(service)}
    supervisor instance name: #{inspect(supervisor)}


    """
  end
end

defmodule BirdSong.Services.Supervisor.UnknownOptionKeyError do
  defexception [:keys, :module]

  def message(%__MODULE__{keys: keys, module: module}) do
    """
    \n\n

    Unknown key provided to #{inspect(module)}

    #{keys |> Enum.map(&inspect(&1)) |> Enum.join("\n")}


    """
  end
end
