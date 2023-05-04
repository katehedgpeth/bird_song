defmodule BirdSong.Services.MacaulayLibrary do
  use BirdSong.Services.Supervisor,
    base_url: "https://search.macaulaylibrary.org",
    caches: [:Recordings],
    other_children: [:Playwright],
    use_data_folder?: true

  alias BirdSong.Bird

  @type request_data() :: Bird.t()
end
