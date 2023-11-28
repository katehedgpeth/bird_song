defmodule BirdSong.MockDataAttributes do
  def endpoint(service, request_data \\ %BirdSong.Bird{sci_name: ""}) do
    service.endpoint(request_data)
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

      @xeno_canto_path BirdSong.MockDataAttributes.endpoint(XenoCanto.Recordings)
      @flickr_path BirdSong.MockDataAttributes.endpoint(Flickr.PhotoSearch)
      @ebird_observations_path BirdSong.MockDataAttributes.endpoint(
                                 Ebird.Observations,
                                 {:recent_observations, ":region"}
                               )
    end
  end
end
