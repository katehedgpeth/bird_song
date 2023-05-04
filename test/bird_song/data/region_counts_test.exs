defmodule BirdSong.Data.RegionCountsTest do
  use BirdSong.DataCase

  alias BirdSong.{
    Data.RegionCounts,
    Services,
    Services.Ebird,
    Services.Ebird.Regions.Region,
    Services.Worker
  }

  setup do
    assert %Services{ebird: %Ebird{Regions: %Worker{} = regions}} = Services.all()
    {:ok, service: regions}
  end

  describe "&get_region_counts/3 for all regions" do
    test "returns the total number of known countries and subregions", %{service: service} do
      raw_countries =
        "data/regions/ebird/all-countries.json"
        |> File.read!()
        |> Jason.decode!()

      assert length(raw_countries) === 253

      counts = RegionCounts.get(service, %{})

      assert %RegionCounts{
               # = _country_counts,
               country_counts: %{} = country_regions,
               country_regions: %{},
               total_countries: total_countries,
               total_regions: total_regions,
               total_subnational1: total_subnational1,
               total_subnational2: total_subnational2
             } = counts

      assert Kernel.map_size(country_regions) === 253

      assert total_countries === 253
      assert total_regions === 14578
      assert total_subnational1 === 3684
      assert total_subnational2 === 10841

      assert total_regions - (total_subnational1 + total_subnational2) === MapSet.size(no_sub1())
    end
  end

  describe "&get_region_counts/3 for a country with subnational2 regions" do
    test "returns the total number of known subregions for a subnational1 region", %{
      service: service
    } do
      counts = RegionCounts.get(service, %{region: "US-NC"})

      assert %RegionCounts{
               country_counts: country_counts,
               country_regions: country_regions,
               total_countries: total_countries,
               total_regions: total_regions,
               total_subnational1: total_subnational1,
               total_subnational2: total_subnational2
             } = counts

      assert Map.keys(country_regions) === ["US"]
      assert Enum.map(country_regions["US"][:subnational1], & &1.code) === ["US-NC"]

      counties = country_regions["US"][:subnational2]
      assert counties |> MapSet.new() |> MapSet.size() === length(counties)

      for county <- counties do
        assert %Region{code: code} = county
        assert "US-NC-" <> _ = code
      end

      assert Map.keys(country_counts) === ["US"]
      assert country_counts["US"][:subnational1] === 1
      assert country_counts["US"][:subnational2] === 100

      assert total_countries === 1
      assert total_regions === 101
      assert total_subnational1 === 1
      assert total_subnational2 === 100
    end
  end

  describe "&get_region_counts/3 for a country without subnational2 regions" do
    test "returns the total number of known subregions for the country", %{
      service: service
    } do
      counts = RegionCounts.get(service, %{region: "AF"})

      assert %RegionCounts{
               country_counts: %{} = country_counts,
               country_regions: %{} = country_regions,
               total_countries: total_countries,
               total_regions: total_regions,
               total_subnational1: total_subnational1,
               total_subnational2: total_subnational2
             } = counts

      assert total_countries === 1
      assert total_regions === 35
      assert total_subnational1 === 34
      assert total_subnational2 === 0

      assert Map.keys(country_regions) === ["AF"]
      assert %{"AF" => subregions} = country_regions
      assert Map.keys(subregions) === [:country, :subnational1]
      assert [%Region{code: "AF"}] = Map.fetch!(subregions, :country)
      sub1 = Map.fetch!(subregions, :subnational1)
      assert [%Region{} | _] = sub1
      assert sub1 |> MapSet.new() |> MapSet.size() === length(sub1)

      for sub <- sub1 do
        assert %Region{code: code} = sub
        assert ["AF", _] = String.split(code, "-")
      end

      assert Map.keys(country_counts) === ["AF"]
      assert Map.fetch!(country_counts, "AF") === %{subnational1: 34, subnational2: 0}
    end

    test "returns data counts for a subnational1 region", %{
      service: service
    } do
      counts = RegionCounts.get(service, %{region: "AF-BDS"})

      assert %RegionCounts{
               country_counts: %{} = country_counts,
               country_regions: %{} = country_regions,
               total_countries: total_countries,
               total_regions: total_regions,
               total_subnational1: total_subnational1,
               total_subnational2: total_subnational2
             } = counts

      assert total_countries === 1
      assert total_regions === 1
      assert total_subnational1 === 1
      assert total_subnational2 === 0

      assert Map.keys(country_regions) === ["AF"]
      assert %{"AF" => subregions} = country_regions
      assert Map.keys(subregions) === [:subnational1]

      assert Map.fetch!(subregions, :subnational1) === [
               %Region{code: "AF-BDS", level: :subnational1, name: :unknown}
             ]

      assert Map.keys(country_counts) === ["AF"]
      assert Map.fetch!(country_counts, "AF") === %{subnational1: 1, subnational2: 0}
    end
  end

  defp no_sub1() do
    MapSet.new([
      "EH Western Sahara",
      "WF Wallis and Futuna",
      "VG Virgin Islands (British)",
      "VA Vatican City (Holy See)",
      "TC Turks and Caicos Islands",
      "TK Tokelau",
      "SJ Svalbard",
      "GS South Georgia and South Sandwich Islands",
      "SX Sint Maarten",
      "SG Singapore",
      "PM Saint Pierre and Miquelon",
      "MF Saint Martin (French part)",
      "BL Saint Barthélemy",
      "RE Réunion",
      "PN Pitcairn Islands",
      "PS Palestinian Territory",
      "NF Norfolk Island",
      "NU Niue",
      "NC New Caledonia",
      "MS Montserrat",
      "MC Monaco",
      "YT Mayotte",
      "MQ Martinique",
      "MO Macau",
      "XK Kosovo",
      "JE Jersey",
      "IM Isle of Man",
      "HK Hong Kong",
      "XX High Seas",
      "HM Heard Island and McDonald Islands",
      "GG Guernsey",
      "GU Guam",
      "GP Guadeloupe",
      "GL Greenland",
      "GI Gibraltar",
      "TF French Southern and Antarctic Lands",
      "GF French Guiana",
      "FO Faroe Islands",
      "FK Falkland Islands (Malvinas)",
      "CW Curaçao",
      "CS Coral Sea Islands",
      "CK Cook Islands",
      "CC Cocos (Keeling) Islands",
      "CP Clipperton Island",
      "CX Christmas Island",
      "IO British Indian Ocean Territory",
      "BV Bouvet Island",
      "BM Bermuda",
      "AC Ashmore and Cartier Islands",
      "AW Aruba",
      "AQ Antarctica",
      "AI Anguilla",
      "AS American Samoa"
    ])
  end
end
