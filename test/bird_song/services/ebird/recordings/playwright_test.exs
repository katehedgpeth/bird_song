defmodule BirdSong.Services.Ebird.Recordings.PlaywrightTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup
  alias BirdSong.{Bird, Services.Ebird.Recordings.Playwright}

  @throttle_ms 1_000

  setup [:seed_from_mock_taxonomy]

  setup do
    [bird | _] = BirdSong.Repo.all(Bird)
    {:ok, server} = Playwright.start_link(bird: bird, throttle_ms: @throttle_ms)

    {:ok, bird: bird, server: server}
  end

  describe "Ebird.Recordings.Playwright.run/1" do
    test "opens a port and returns a response", %{bird: bird, server: server} do
      response = Playwright.run(server)

      assert {:ok, data} = response
      assert is_list(data)
      assert length(data) === 90

      for recording <- data do
        assert %{
                 "ageSex" => _,
                 "assetId" => _,
                 "assetState" => _,
                 "cursorMark" => _,
                 "ebirdChecklistId" => _,
                 "exoticCategory" => _,
                 "height" => _,
                 "licenseId" => _,
                 "location" => _,
                 "mediaNotes" => _,
                 "mediaType" => "audio",
                 "obsDt" => _,
                 "obsDtDisplay" => _,
                 "obsMonth" => _,
                 "obsTime" => _,
                 "obsYear" => _,
                 "parentAssetId" => _,
                 "rating" => _,
                 "ratingCount" => _,
                 "restricted" => _,
                 "reviewed" => _,
                 "source" => _,
                 "tags" => _,
                 "taxonomy" => taxonomy,
                 "userDisplayName" => _,
                 "userHasProfile" => _,
                 "userId" => _,
                 "valid" => _,
                 "width" => _
               } = recording

        assert %Bird{
                 common_name: common_name,
                 sci_name: sci_name,
                 species_code: species_code
               } = bird

        assert Map.keys(taxonomy) === [
                 "category",
                 "comName",
                 "reportAs",
                 "sciName",
                 "speciesCode"
               ]

        assert %{
                 "category" => _,
                 "comName" => ^common_name,
                 "reportAs" => _,
                 "sciName" => ^sci_name,
                 "speciesCode" => ^species_code
               } = taxonomy
      end
    end

    test "sends 3 throttled requests", %{server: server} do
      Playwright.run(server)

      refute_receive {Playwright, %DateTime{}, {:request, %{current_request_number: 0}}}
      refute_receive {Playwright, %DateTime{}, {:request, %{current_request_number: 4}}}

      assert_receive {
        Playwright,
        %DateTime{} = request_1_time,
        {:request, %{current_request_number: 1, responses: []}}
      }

      assert_receive {
                       Playwright,
                       %DateTime{} = request_2_time,
                       {:request, %{current_request_number: 2, responses: responses}}
                     }
                     when length(responses) === 30

      assert_receive {
                       Playwright,
                       %DateTime{} = request_3_time,
                       {:request, %{current_request_number: 3, responses: responses}}
                     }
                     when length(responses) === 60

      assert DateTime.diff(request_2_time, request_1_time, :millisecond) > @throttle_ms
      assert DateTime.diff(request_3_time, request_2_time, :millisecond) > @throttle_ms
    end
  end
end
