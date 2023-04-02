defmodule BirdSong.Data.Counts do
  defstruct missing_images: 0,
            missing_recordings: 0,
            total_birds: 0,
            has_images: 0,
            has_recordings: 0,
            data_folder_bytes: 0

  alias BirdSong.{
    Bird,
    Services,
    Services.Service,
    Services.DataFile
  }

  defmodule NoBirdsError do
    defexception message: "No birds in database!"
  end

  def get(%Services{} = services) do
    {:ok, %File.Stat{size: data_folder_bytes}} = File.stat("data")

    case BirdSong.Repo.all(Bird) do
      [%Bird{} | _] = birds ->
        birds
        |> Enum.reduce(
          %__MODULE__{
            total_birds: length(birds),
            data_folder_bytes: data_folder_bytes
          },
          &add_bird_counts(&1, &2, services)
        )
        |> Map.from_struct()
        |> Enum.map(&print/1)
        |> Enum.into(%{})

      [] ->
        raise NoBirdsError
    end
  end

  def print({:data_folder_bytes = key, val}) do
    IO.inspect("#{val / 1000} KB", label: key)
    {key, val}
  end

  def print({key, val}) do
    IO.inspect(val, label: key)
    {key, val}
  end

  defp add_bird_counts(%Bird{} = bird, %__MODULE__{} = counts, %Services{} = services) do
    Enum.reduce(
      [:images, :recordings],
      counts,
      &(services
        |> Map.fetch!(&1)
        |> add_service_count(bird, &2, &1))
    )
  end

  defp add_service_count(%Service{} = service, %Bird{} = bird, %__MODULE__{} = counts, type) do
    %DataFile.Data{request: bird, service: service}
    |> DataFile.data_file_path()
    |> File.stat()
    |> case do
      {:ok, %File.Stat{type: :regular}} -> :has
      {:error, :enoent} -> :missing
    end
    |> count_key(type)
    |> add_one(counts)
  end

  defp add_one(key, %__MODULE__{} = counts) do
    Map.update!(counts, key, &(&1 + 1))
  end

  defp count_key(status, type) do
    [status, type]
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join("_")
    |> String.to_existing_atom()
  end
end
