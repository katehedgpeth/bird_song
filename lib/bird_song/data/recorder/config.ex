defmodule BirdSong.Data.Recorder.Config do
  alias BirdSong.{Services, Services.Helpers, Services.Ebird.RegionCodes, Services.Service}

  defstruct [
    :region_codes,
    :services,
    :taxonomy_file,
    birds: [],
    clear_db?: false,
    overwrite_files?: false,
    seed_taxonomy?: false
  ]

  def parse(args, services) do
    Enum.reduce(args, %__MODULE__{services: services}, &do_parse(&1, &2, services))
  end

  defp do_parse("--seed-taxonomy", %__MODULE__{} = config, _services) do
    %{config | seed_taxonomy?: true}
  end

  defp do_parse("--taxonomy-file=" <> file, %__MODULE__{} = config, _services) do
    %{config | seed_taxonomy?: true, taxonomy_file: file}
  end

  defp do_parse("--overwrite", %__MODULE__{} = config, _services) do
    %{config | overwrite_files?: true}
  end

  defp do_parse("--bird=" <> common_name, %__MODULE__{} = config, _services) do
    bird = BirdSong.Repo.get_by!(Bird, common_name: String.replace(common_name, "_", " "))

    %{config | birds: [bird]}
  end

  defp do_parse("--region=" <> region, %__MODULE__{} = config, %Services{
         region_codes: service
       }) do
    %{config | region_codes: get_region_codes(region, service)}
  end

  defp do_parse("" <> arg, %__MODULE__{}, _services) do
    raise "unexpected argument: " <> arg
  end

  defp get_region_codes(region, %Service{} = service) do
    case RegionCodes.get({:region_codes, region}, service) do
      {:ok, %RegionCodes.Response{codes: codes}} ->
        MapSet.new(codes)

      {:error, _} ->
        Helpers.log([error: "unknown_region_code", region_code: region], __MODULE__, :warning)
        MapSet.new([])
    end
  end
end
