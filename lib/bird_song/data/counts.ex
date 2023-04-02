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
    case BirdSong.Repo.all(Bird) do
      [%Bird{} | _] = birds ->
        Enum.reduce(
          birds,
          %__MODULE__{
            total_birds: length(birds),
            data_folder_bytes: calculate_data_folder_bytes(services)
          },
          &add_bird_counts(&1, &2, services)
        )

      [] ->
        raise NoBirdsError
    end
  end

  defp calculate_data_folder_bytes(%Services{images: images, recordings: recordings}) do
    Enum.reduce([images, recordings], 0, &(&2 + get_data_folder_bytes(&1)))
  end

  def get_data_folder_bytes(%Service{} = service) do
    service
    |> Service.module()
    |> apply(:data_folder_path, [service])
    |> File.stat!()
    |> Map.fetch!(:size)
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
