defmodule BirdSong.Services.Ebird.RegionETSTest do
  use BirdSong.SupervisedCase, async: true

  alias BirdSong.Services.{
    Ebird,
    Ebird.RegionETS
  }

  test "get", %{} = tags do
    assert %{worker: worker} = get_worker_setup(Ebird, :RegionETS, tags)

    assert RegionETS.get("US-NC-067", worker) ===
             {:ok,
              %Ebird.Region{
                code: "US-NC-067",
                name: "Forsyth",
                level: :subnational2
              }}
  end
end
