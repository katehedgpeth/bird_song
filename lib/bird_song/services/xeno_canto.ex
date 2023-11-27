defmodule BirdSong.Services.XenoCanto do
  use BirdSong.Services.Supervisor,
    base_url: "https://xeno-canto.org/",
    caches: [:Recordings],
    other_children: [],
    use_data_folder?: true,
    timeout: :infinity,
    allow_external_calls?: true

  alias BirdSong.Bird

  @type request_data() :: Bird.t()
end
