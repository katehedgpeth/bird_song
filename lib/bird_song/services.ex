defmodule BirdSong.Services do
  use GenServer

  alias __MODULE__.{
    Ebird,
    Flickr,
    Service
  }

  @recordings :bird_song
              |> Application.compile_env!(__MODULE__)
              |> Keyword.fetch!(:recordings)

  @service_keys MapSet.new([
                  :images,
                  :recordings,
                  :ebird
                ])

  @supervisors [:ebird, :images]
  @gen_servers [:recordings]

  defstruct ebird: Ebird,
            images: Flickr,
            recordings: %Service{
              module: @recordings
            }

  @type t() :: %__MODULE__{
          ebird: Ebird.t(),
          images: Flickr.t(),
          recordings: Service.t()
        }

  def ensure_started() do
    Enum.reduce(
      @service_keys,
      %__MODULE__{},
      &do_ensure_started/2
    )
  end

  defp do_ensure_started(key, %__MODULE__{} = state) when key in @supervisors do
    Map.update!(state, key, & &1.services())
  end

  defp do_ensure_started(key, %__MODULE__{} = state) when key in @gen_servers do
    Map.update!(state, key, &Service.ensure_started!/1)
  end

  def start_link(%__MODULE__{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @spec init(BirdSong.Services.t()) :: {:ok, BirdSong.Services.t()}
  def init(%__MODULE__{} = state) do
    {:ok, state}
  end
end
