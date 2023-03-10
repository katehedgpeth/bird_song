defmodule BirdSong.MockDataAttributes do
  defmacro __using__([]) do
    quote location: :keep do
      alias BirdSong.Bird
      alias BirdSong.Services.XenoCanto
      alias BirdSong.Services.Flickr

      @red_shouldered_hawk %Bird{
        sci_name: "Buteo lineatus",
        common_name: "Red-shouldered Hawk",
        species_code: "reshaw"
      }
      @carolina_wren %Bird{
        sci_name: "Thryothorus ludovicianus",
        common_name: "Carolina Wren",
        species_code: "carwre"
      }
      @eastern_bluebird %Bird{
        sci_name: "Sialia sialis",
        common_name: "Eastern Bluebird",
        species_code: "easblu"
      }
      @mocked_birds [@red_shouldered_hawk, @carolina_wren, @eastern_bluebird]

      @birds_by_sci_name Enum.reduce(
                           [@red_shouldered_hawk, @carolina_wren, @eastern_bluebird],
                           %{},
                           fn bird, acc -> Map.put(acc, bird.sci_name, bird) end
                         )

      @xeno_canto_path @red_shouldered_hawk
                       |> XenoCanto.url()
                       |> URI.parse()
                       |> Map.get(:path)
      @flickr_path %Bird{} |> Flickr.url() |> URI.parse() |> Map.get(:path)
    end
  end
end
