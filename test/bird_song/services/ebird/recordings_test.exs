defmodule BirdSong.Services.Ebird.RecordingsTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup
  alias BirdSong.{}

  alias BirdSong.{
    Bird,
    Services,
    Services.Ebird.Recordings,
    Services.Service,
    Services.ThrottledCache,
    TestHelpers
  }

  @moduletag :tmp_dir

  setup [:seed_from_mock_taxonomy]
  setup [:start_services]

  setup do
    TestHelpers.update_env(ThrottledCache, :throttle_ms, 0)

    :ok
  end

  @tag recordings_module: Recordings
  test "get_from_api/1", %{
    services: %Services{recordings: service}
  } do
    assert %Service{module: Recordings} = service
    bird = BirdSong.Repo.get_by(Bird, common_name: "Eastern Bluebird")
    assert {:ok, %Recordings.Response{recordings: recordings}} = Recordings.get(bird, service)
    assert is_list(recordings)
    assert length(recordings) === 90

    for recording <- recordings do
      assert %Recordings.Recording{asset_id: asset_id, location: location} = recording
      assert is_integer(asset_id)
      assert is_map(location)

      assert Map.keys(location) === [
               "countryCode",
               "countryName",
               "latitude",
               "locId",
               "locality",
               "localityDir",
               "localityKm",
               "longitude",
               "name",
               "subnational1Code",
               "subnational1Name",
               "subnational2Code",
               "subnational2Name"
             ]
    end

    # File.write()
    # assert Map.keys(recording) === []
    # assert_receive :FAIL
  end
end
