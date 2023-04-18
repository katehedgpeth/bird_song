defmodule BirdSong.Data.Counts do
  defstruct missing_images: 0,
            missing_recordings: 0,
            total_birds: 0,
            has_images: 0,
            has_recordings: 0,
            data_folder_bytes: 0

  alias BirdSong.Services.Helpers
  alias BirdSong.Services.Ebird.RegionSpeciesCodes

  alias BirdSong.{
    Bird,
    Services,
    Services.Service,
    Services.DataFile
  }

  defmodule NoBirdsError do
    defexception message: "No birds in database!"
  end

  def get(%Services{} = services, args) do
    region_species_codes =
      get_region_species_codes(args, Map.fetch!(services, :region_species_codes))

    size = MapSet.size(region_species_codes)

    Bird
    |> BirdSong.Repo.all()
    |> Enum.filter(&keep_bird?(size, region_species_codes, &1))
    |> case do
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

  defp calculate_data_folder_bytes(%Services{} = services) do
    services
    |> Map.from_struct()
    |> Enum.reduce(0, &(&2 + get_data_folder_bytes(&1)))
  end

  defp keep_bird?(0, _codes, %Bird{}), do: true
  defp keep_bird?(_, codes, %Bird{species_code: code}), do: MapSet.member?(codes, code)

  defp get_data_folder_bytes({_, %Service{} = service}) do
    folder =
      service
      |> Service.module()
      |> apply(:data_folder_path, [service])

    case File.stat(folder) do
      {:ok, %{type: :directory}} -> get_folder_size(%{name: folder}, 0)
      {:error, :enoent} -> 0
    end
  end

  defp get_data_folder_bytes({key, _})
       when key in [:__tasks, :overwrite?, :__from, :bird, :timeout],
       do: 0

  def get_folder_size(%{name: folder_name}, size) do
    folder_name
    |> File.ls!()
    |> Enum.map(&Path.join(folder_name, &1))
    |> Enum.map(&%{name: &1, stats: File.lstat!(&1)})
    |> Enum.group_by(& &1[:stats].type)
    |> Enum.reduce(size, &do_get_folder_size/2)
  end

  defp do_get_folder_size({:directory, files_or_folders}, size) do
    Enum.reduce(files_or_folders, size, &get_folder_size/2)
  end

  defp do_get_folder_size({:regular, files}, size) do
    Enum.reduce(files, size, &get_file_size/2)
  end

  defp get_file_size(%{name: _, stats: %File.Stat{size: file_size}}, acc) do
    acc + file_size
  end

  defp get_region_species_codes(%{region: region}, %Service{module: RegionSpeciesCodes} = service) do
    case RegionSpeciesCodes.get({:region_species_codes, region}, service) do
      {:ok, %RegionSpeciesCodes.Response{codes: codes}} ->
        MapSet.new(codes)

      {:error, _} ->
        Helpers.log([error: "unknown_region_code", region_code: region], __MODULE__, :warning)
        get_region_species_codes(%{}, service)
    end
  end

  defp get_region_species_codes(%{}, %Service{}), do: MapSet.new([])

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
    service.whereis
    |> GenServer.call(:state)
    |> Map.fetch!(:data_file_instance)
    |> GenServer.call({:data_file_path, %DataFile.Data{request: bird, service: service}})
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
