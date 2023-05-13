defmodule BirdSong.Region do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias BirdSong.Services.Ebird

  @known_dupes [
    "Echizen, Fukui, Japan",
    "Esashi, Hokkaido, Japan",
    "Fuchu, Hiroshima, Japan",
    "Kiso, Nagano, Japan",
    "Kushiro, Hokkaido, Japan",
    "Matsukawa, Nagano, Japan",
    "Misato, Saitama, Japan",
    "Shibetsu, Hokkaido, Japan",
    "Shimanto, Kochi, Japan",
    "Shirakawa, Gifu, Japan",
    "Tosa, Kochi, Japan",
    "Narrogin, Western Australia, Australia"
  ]

  schema "regions" do
    field :code, :string
    field :full_name, :string
    field :level, Ecto.Enum, values: [:country, :subnational1, :subnational2]
    field :max_lat, :float
    field :max_lon, :float
    field :min_lat, :float
    field :min_lon, :float
    field :short_name, :string
    timestamps()
  end

  def all() do
    BirdSong.Repo.all(__MODULE__)
  end

  def from_code!("" <> code) do
    BirdSong.Repo.one!(from r in __MODULE__, where: r.code == ^code)
  end

  @doc false
  def changeset(region, attrs) do
    region
    |> cast(attrs, [
      :code,
      :short_name,
      :full_name,
      :min_lat,
      :max_lat,
      :min_lon,
      :max_lon,
      :level
    ])
    |> validate_required([
      :code,
      :short_name,
      :full_name,
      :min_lat,
      :max_lat,
      :min_lon,
      :max_lon,
      :level
    ])
    |> unique_constraint(:full_name)
    |> unique_constraint(:code)
  end

  def seed([%Ebird.Region{} | _] = regions) do
    regions
    |> Enum.map(&to_struct/1)
    |> Enum.reject(&(&1[:full_name] in @known_dupes))
    |> Enum.chunk_every(3000)
    |> Enum.map(&do_seed/1)
  end

  def do_seed(regions) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert_all(:insert_all, __MODULE__, regions)
    |> BirdSong.Repo.transaction()
  end

  def to_struct(%Ebird.Region{} = region) do
    timestamp =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.truncate(:second)

    %Ebird.RegionInfo.Response{data: info} =
      File.read!("data/region_info/ebird/#{region.code}.json")
      |> Jason.decode!()
      |> Ebird.RegionInfo.Response.parse({:region_info, region})

    [
      code: region.code,
      short_name: region.name,
      level: region.level,
      full_name: info.name,
      min_lat: info.min_lat,
      max_lat: info.max_lat,
      min_lon: info.min_lon,
      max_lon: info.max_lon,
      inserted_at: timestamp,
      updated_at: timestamp
    ]
  end
end
