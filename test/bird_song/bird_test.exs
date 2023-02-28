defmodule BirdSong.BirdTest do
  use ExUnit.Case

  alias BirdSong.{
    Bird,
    Services
  }

  alias Services.{
    XenoCanto.Response,
    Ebird.Observation
  }

  @response "test/mock_data/Buteo_lineatus.json"
            |> Path.relative_to_cwd()
            |> File.read!()
            |> Jason.decode!()
            |> Response.parse()

  @observation "test/mock_data/recent_observations.json"
               |> Path.relative_to_cwd()
               |> File.read!()
               |> Jason.decode!()
               |> List.first()
               |> Observation.parse()

  describe "&Bird.new/1" do
    test "from Response" do
      assert Bird.new(@response) ===
               %Bird{
                 common_name: "Red-shouldered Hawk",
                 sci_name: "Buteo lineatus",
                 ebird_code: ""
               }
    end

    test "from Observation" do
      assert Bird.new(@observation) ==
               %Bird{
                 common_name: "Carolina Wren",
                 sci_name: "Thryothorus ludovicianus",
                 ebird_code: "carwre"
               }
    end
  end
end
