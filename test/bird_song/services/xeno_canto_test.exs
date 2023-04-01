defmodule BirdSong.Services.XenoCantoTest do
  use BirdSong.MockApiCase
  alias BirdSong.Services

  alias Services.{
    Service,
    XenoCanto,
    XenoCanto.Response,
    XenoCanto.Recording
  }

  @moduletag services: [:xeno_canto]
  @moduletag recordings_module: XenoCanto
  @moduletag bird: @eastern_bluebird

  setup %{
    services: %Services{
      recordings: %Service{module: XenoCanto, whereis: whereis}
    }
  } do
    {:ok, whereis: whereis}
  end

  describe "&get/1" do
    @describetag stub: {"GET", "/api/2/recordings", &MockServer.success_response/1}

    test "returns a response object when request is successful", %{
      bird: bird,
      whereis: whereis
    } do
      assert XenoCanto.get_from_cache(bird, whereis) === :not_found
      assert {:ok, response} = XenoCanto.get(bird, whereis)
      assert %Response{recordings: recordings} = response
      assert length(recordings) == 153
      assert [%Recording{} | _] = recordings
    end

    @tag :skip
    test "changes :also to common names when found", %{bird: bird, whereis: whereis} do
      assert {:ok, %Response{recordings: recordings}} = XenoCanto.get(bird, whereis)

      assert %Recording{
               also: [
                 "Tufted Titmouse",
                 "Northern Parula",
                 "Northern Cardinal"
               ]
             } = Enum.filter(recordings, &(length(&1.also) > 2)) |> Enum.at(5)
    end
  end
end
