defmodule BirdSong.Region do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias BirdSong.Services.Ebird

  @derive {Jason.Encoder,
           only: [
             :code,
             :full_name,
             :max_lat,
             :max_lon,
             :min_lat,
             :min_lon,
             :short_name
           ]}

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

  def filter_by_name(name) do
    name = String.downcase(name)

    __MODULE__
    |> BirdSong.Repo.all()
    |> Enum.filter(fn %{short_name: short_name} -> String.downcase(short_name) =~ name end)
  end

  def from_code!("" <> code) do
    code
    |> from_code_query()
    |> BirdSong.Repo.one!()
  end

  def from_code("" <> code) do
    code
    |> from_code_query()
    |> BirdSong.Repo.one()
  end

  defp from_code_query("" <> code) do
    from r in __MODULE__, where: r.code == ^code
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
    |> Enum.map(&build_params/1)
    |> Enum.reject(&(&1[:full_name] in @known_dupes))
    |> Enum.chunk_every(3000)
    |> Enum.with_index()
    |> Enum.reduce(Ecto.Multi.new(), &do_seed/2)
  end

  def seed!([%Ebird.Region{} | _] = regions) do
    regions
    |> seed()
    |> BirdSong.Repo.transaction()
    |> case do
      {:ok, regions} -> regions
      {:error, error} -> error
    end
  end

  def do_seed({regions, idx}, multi) when is_list(regions) do
    Ecto.Multi.insert_all(multi, :"insert_all_regions_#{idx}", __MODULE__, regions)
  end

  def build_params(%Ebird.Region{} = region) do
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
