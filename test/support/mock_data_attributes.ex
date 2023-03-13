defmodule BirdSong.MockDataAttributes do
  def url_path(service, request_data \\ %BirdSong.Bird{sci_name: ""}) do
    request_data
    |> service.url()
    |> URI.parse()
    |> Map.fetch!(:path)
  end

  defmacro __using__([]) do
    quote location: :keep,
          bind_quoted: [] do
      alias BirdSong.{
        Bird,
        Services.Ebird,
        Services.Flickr,
        Services.XenoCanto
      }

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

      @xeno_canto_path BirdSong.MockDataAttributes.url_path(XenoCanto)
      @flickr_path BirdSong.MockDataAttributes.url_path(Flickr)
      @ebird_path BirdSong.MockDataAttributes.url_path(Ebird, {:recent_observations, ":region"})
    end
  end
end
