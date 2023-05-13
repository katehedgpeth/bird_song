defmodule BirdSong.Services.Ebird.RegionInfo.Response do
  alias BirdSong.Services.Ebird.{Region, RegionInfo}
  defstruct [:data]

  def parse(
        %{"result" => "" <> name} = response,
        {:region_info, %Region{code: code}}
      ) do
    %__MODULE__{
      data:
        response
        |> Map.get("bounds")
        |> parse_bounds()
        |> Map.replace!(:code, code)
        |> Map.replace!(:name, name)
    }
  end

  defp parse_bounds(%{
         "maxY" => max_lat,
         "maxX" => max_lon,
         "minY" => min_lat,
         "minX" => min_lon
       }),
       do: do_parse_bounds([max_lat, max_lon, min_lat, min_lon])

  defp parse_bounds(nil) do
    1..4
    |> Enum.map(fn _ -> nil end)
    |> do_parse_bounds()
  end

  defp do_parse_bounds([max_lat, max_lon, min_lat, min_lon]) do
    %RegionInfo{
      max_lat: max_lat,
      max_lon: max_lon,
      min_lat: min_lat,
      min_lon: min_lon
    }
  end
end
