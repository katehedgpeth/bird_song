defmodule BirdSong.ServicesTest do
  use BirdSong.MockApiCase
  alias BirdSong.Services

  @tag :capture_log
  @tag use_mock_routes?: false
  test "ensure_started/0 returns running instances without raising an error" do
    services = Services.ensure_started()
    assert %Services{} = services
  end
end
