defmodule Mix.Tasks.BirdSong.RecordRegions do
  use Mix.Task
  @requirements ["app.config", "app.start"]

  alias BirdSong.{
    Services.Ebird,
    Services.Ebird.Region,
    Services.Ebird.Regions,
    Services.Ebird.RegionInfo,
    Services.Worker
  }

  def run(
        args,
        %Worker{} = regions_service \\ Ebird.get_instance_child(:Regions),
        %Worker{} = region_info_service \\ Ebird.get_instance_child(:RegionInfo)
      ) do
    GenServer.cast(regions_service.instance_name, {:update_write_config, true})
    GenServer.cast(region_info_service.instance_name, {:update_write_config, true})

    args
    |> parse_region()
    |> case do
      :all -> Regions.get_all(regions_service)
    end
    |> get_regions_info(region_info_service)
  end

  defp get_regions_info({:error, error}, %Worker{}) do
    raise error
  end

  defp get_regions_info({:ok, [%Region{} | _] = regions}, %Worker{} = service) do
    regions
    |> Task.async_stream(&get_region_info!(&1, service), timeout: :infinity)
    |> Enum.map(fn {:ok, info} -> info end)
  end

  defp get_region_info!(%Region{} = region, %Worker{} = service) do
    case RegionInfo.get_info(region, service) do
      {:ok, %RegionInfo{} = info} -> info
      {:error, error} -> raise error
    end
  end

  # defp get_region_info([], acc, %Service{}) do
  #   {:ok, acc}
  # end

  # defp get_region_info([%Region{code: code} = region | rest], acc, %Service{} = service) do
  #   case RegionInfo.get_info(region, service) do
  #     {:ok, %RegionInfo{} = info} ->
  #       get_region_info(rest, Map.put(acc, code, %{region: region, info: info}), service)

  #     {:error, error} ->
  #       raise error
  #   end
  # end

  @spec parse_region([String.t()]) :: :all | {String.t(), Region.level()}
  defp parse_region([]), do: :all

  defp parse_region(["--parent-region=" <> region]) do
    {region, parse_level(region)}
  end

  defp parse_level(<<_country_code::binary-size(2), "-", _subnational_1::binary-size(2)>>) do
    :subnational_2
  end

  defp parse_level(<<_country_code::binary-size(2), "-", _subnational_1::binary-size(3)>>) do
    :subnational_2
  end

  defp parse_level(<<_country_code::binary-size(2)>>) do
    :subnational_1
  end
end
