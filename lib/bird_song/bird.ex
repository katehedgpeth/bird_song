defmodule BirdSong.Bird do
  use Ecto.Schema
  import Ecto.Query, only: [from: 2]

  alias BirdSong.{
    Family,
    Order,
    Services.Ebird.RegionSpeciesCodes,
    Services.Ebird.Taxonomy
  }

  @behaviour Taxonomy

  @derive {Inspect, only: [:common_name, :id, :sci_name]}
  @derive {Jason.Encoder,
           only: [
             :id,
             :species_code,
             :common_name,
             :sci_name,
             :category,
             :taxon_order,
             :banding_codes,
             :common_name_codes,
             :sci_name_codes,
             :family,
             :order
           ]}

  @cast_keys [
    :species_code,
    :common_name,
    :sci_name,
    :category,
    :taxon_order,
    :banding_codes,
    :common_name_codes,
    :sci_name_codes
  ]

  schema "birds" do
    field :species_code, :string
    field :common_name, :string
    field :sci_name, :string
    field :category, :string
    field :taxon_order, :float
    field :report_as, :string
    field :banding_codes, {:array, :string}, default: []
    field :common_name_codes, {:array, :string}, default: []
    field :sci_name_codes, {:array, :string}, default: []
    field :has_recordings?, :boolean, default: false
    field :has_images?, :boolean, default: false
    belongs_to :family, Family
    belongs_to :order, Order
    many_to_many :quizzes, BirdSong.Quiz, join_through: "birds_quizzes"
  end

  @type common_name() :: String.t()

  @type t() :: %__MODULE__{
          sci_name: String.t(),
          common_name: common_name(),
          species_code: String.t(),
          category: String.t(),
          taxon_order: Integer.t(),
          report_as: String.t(),
          banding_codes: [String.t()],
          common_name_codes: [String.t()],
          sci_name_codes: [String.t()],
          has_recordings?: boolean(),
          has_images?: boolean()
        }

  @impl Taxonomy
  def uid_raw_key(), do: "speciesCode"

  @impl Taxonomy
  def uid_struct_key(), do: :species_code

  def family_name(%__MODULE__{family: %Family{common_name: family_name}}) do
    family_name
  end

  @spec get!(integer()) :: Bird.t()
  def get!(id) do
    BirdSong.Repo.get!(__MODULE__, id)
  end

  @spec get_by_sci_name(String.t()) :: {:ok, Bird.t()} | {:error, {:not_found, String.t()}}
  def get_by_sci_name("" <> sci_name) do
    case BirdSong.Repo.get_by(__MODULE__, sci_name: sci_name) do
      %__MODULE__{} = bird -> {:ok, BirdSong.Repo.preload(bird, [:family, :order])}
      nil -> {:error, {:not_found, sci_name}}
    end
  end

  def get_many_by_sci_name(["" <> _ | _] = sci_names) do
    BirdSong.Repo.all(
      from b in __MODULE__,
        where: b.sci_name in ^sci_names
    )
  end

  def get_many_by_id([]) do
    []
  end

  def get_many_by_id(ids) when is_list(ids) do
    ids
    |> get_many_by_id_query()
    |> BirdSong.Repo.all()
  end

  def get_many_by_id_query(ids) when is_list(ids) do
    from bird in __MODULE__,
      where: bird.id in ^ids,
      preload: [:family, :order]
  end

  def get_many_by_common_name(["" <> _ | _] = common_names) do
    BirdSong.Repo.all(
      from b in __MODULE__,
        where: b.common_name in ^common_names
    )
  end

  def get_many_by_species_code([]), do: []

  def get_many_by_species_code(["" <> _ | _] = species_codes) do
    BirdSong.Repo.all(
      from b in __MODULE__,
        where: b.species_code in ^species_codes,
        preload: [:family, :order]
    )
  end

  def get_many_by_species_code({:ok, %RegionSpeciesCodes.Response{codes: codes}}),
    do: {:ok, get_many_by_species_code(codes)}

  def get_many_by_species_code({:error, error}), do: {:error, error}

  @impl Taxonomy
  def params_from_raw(
        %{
          "sciName" => sci_name,
          "comName" => common_name,
          "speciesCode" => species_code,
          "category" => category,
          "taxonOrder" => taxon_order,
          "bandingCodes" => banding_codes,
          "comNameCodes" => common_name_codes,
          "sciNameCodes" => sci_name_codes
        } = raw
      ) do
    report_as = Map.get(raw, "reportAs")

    %{
      sci_name: sci_name,
      common_name: common_name,
      species_code: species_code,
      category: category,
      taxon_order: taxon_order,
      report_as: report_as,
      banding_codes: banding_codes,
      common_name_codes: common_name_codes,
      sci_name_codes: sci_name_codes
    }
  end

  def cast_keys() do
    @cast_keys
  end
end
