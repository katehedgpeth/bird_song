defmodule BirdSong.Services.Ebird.RegionTest do
  require Logger
  use ExUnit.Case, async: true

  alias BirdSong.Services.{
    Ebird,
    Ebird.Region,
    Ebird.Region.MalformedRegionCodeError
  }

  setup_all [:get_countries, :get_subnat1, :get_subnat2]

  @integers ~s(1234567890) |> String.split("", trim: true)
  @uppercase ~s(ABCDEFGHIJKLMNOPQRSTUVWXYZ) |> String.split("", trim: true)

  describe "&parse/1" do
    test "parses a subnational2 region code" do
      assert Ebird.Region.parse(%{"code" => "US-NC-067", "name" => "Forsyth"}) ===
               %Ebird.Region{
                 code: "US-NC-067",
                 level: :subnational2,
                 name: "Forsyth"
               }
    end

    test "parses a subnational1 region code" do
      assert Ebird.Region.parse(%{"code" => "US-NC", "name" => "North Carolina"}) ===
               %Ebird.Region{
                 code: "US-NC",
                 level: :subnational1,
                 name: "North Carolina"
               }
    end

    test "parses a country region code" do
      assert Ebird.Region.parse(%{"code" => "US", "name" => "United States"}) ===
               %Ebird.Region{
                 code: "US",
                 level: :country,
                 name: "United States"
               }
    end
  end

  describe "&parse_level/1" do
    test "parses country codes", %{countries: countries} do
      assert length(countries) === 3

      for code <- countries do
        assert %{code: code, level: :country} = code
        level = Region.parse_level(code)

        assert level === {:ok, :country},
               "expected #{inspect(code)} to be :country, but got: #{inspect(level)}"
      end
    end

    test "parses subnational1 codes", %{subnat1: subnat1} do
      assert length(subnat1) === 33

      for region <- subnat1 do
        assert %{code: code, level: :subnational1} = region
        level = Region.parse_level(code)

        assert level === {:ok, :subnational1},
               "expected #{inspect(code)} to be :subnational1, but got: #{inspect(level)}"

        assert [_, sub1] = String.split(code, "-")

        assert_well_formed_sub_code(sub1, region, [1, 3], :subnational1)
      end
    end

    test "parses subnational2 codes", %{subnat2: subnat2} do
      assert length(subnat2) === 912

      for region <- subnat2 do
        assert %{code: code, level: :subnational2} = region
        level = Region.parse_level(code)

        assert level === {:ok, :subnational2},
               "expected #{inspect(code)} to be :subnational2, but got: #{inspect(level)}"

        assert [_, _, sub2] = String.split(code, "-")
        assert_well_formed_sub_code(sub2, region, [2, 3], :subnational2)
      end
    end

    test "returns a MalformedRegionCodeError if region code is not formatted correctly" do
      assert Region.parse_level("0US") === {:error, %MalformedRegionCodeError{code: "0US"}}
    end
  end

  describe "get_parent/2" do
    test "returns country for a subnational1 code", %{subnat1: subnational1_regions} do
      Task.async_stream(subnational1_regions, fn region ->
        assert %Region{level: :subnational1} = region
        assert {:ok, country} = Region.get_parent(region)
        assert %Region{level: :country} = country
        assert String.starts_with?(region.code, country.code <> "-")
      end)
    end
  end

  defp assert_well_formed_sub_code(sub, region, [min_length, max_length], level) do
    assert %Region{} = region

    assert String.length(sub) in Range.new(min_length, max_length),
           """
           expected #{inspect(sub)} to have between #{inspect(min_length)} and #{inspect(max_length)} characters
           region: #{inspect(region)}
           """

    ints_or_letters =
      case sub do
        <<integer::binary-size(1), _::binary>> when integer in @integers -> @integers
        <<letter::binary-size(1), _::binary>> when letter in @uppercase -> @uppercase
      end

    unless level === :subnational2 and alphanum_sub2?(region) do
      for char <- String.split(sub, "", trim: true) do
        assert <<char::binary-size(1)>> = char

        assert char in ints_or_letters,
               """
               expected #{inspect(sub)} to be all integers or all letters
               region: #{inspect(region)}
               """
      end
    end
  end

  defp alphanum_sub2?(%Region{code: <<country_code::binary-size(2), _::binary>>}) do
    country_code in ["DE", "FR"]
  end

  def get_countries(_) do
    {:ok,
     countries:
       %Region{code: "world"}
       |> read_region_file([])
       |> Enum.filter(&include_country?/1)}
  end

  def get_subnat1(%{} = tags) do
    {:ok, subnat1: get_subregions(tags, :countries)}
  end

  defp get_subnat2(%{} = tags) do
    {:ok, subnat2: get_subregions(tags, :subnat1)}
  end

  defp get_subregions(tags, parent_regions_key) do
    tags
    |> Map.fetch!(parent_regions_key)
    |> Enum.reduce([], &read_region_file(&1, &2))
  end

  defp include_country?(%Region{name: "" <> name}) do
    name in [
      # no sub1
      "High Seas",
      # no sub2
      "Jamaica",
      # has both
      "Spain"
    ]
  end

  defp region_file_name(%Region{code: "world"}) do
    "world-country"
  end

  defp region_file_name(%Region{code: country_code, level: :country}) do
    country_code <> "-subnational1"
  end

  defp region_file_name(%Region{
         code: <<country_code::binary-size(2), _::binary>>,
         level: :subnational1
       }) do
    country_code <> "-subnational2"
  end

  defp read_region_file(%Region{} = region, acc) do
    "data/regions/ebird"
    |> Path.join(region_file_name(region) <> ".json")
    |> File.read()
    |> case do
      {:ok, json} ->
        json
        |> Jason.decode!()
        |> Enum.map(&Region.parse/1)
        |> Enum.reduce(acc, &[&1 | &2])

      {:error, :enoent} ->
        Logger.warning(
          "skipping #{region.code} because file #{region_file_name(region)}.json does not exist"
        )

        acc
    end
  end
end
