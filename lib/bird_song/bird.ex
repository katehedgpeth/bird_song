defmodule BirdSong.Bird do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]
  alias BirdSong.Services.Ebird.RegionSpeciesCodes
  alias BirdSong.{Family, Order}

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
  @assoc_keys [:family, :order]

  @required_keys @cast_keys ++ @assoc_keys

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
  end

  @type t() :: %__MODULE__{
          sci_name: String.t(),
          common_name: String.t(),
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

  def get_many_by_species_code([]), do: []

  def get_many_by_species_code(["" <> _ | _] = species_codes) do
    BirdSong.Repo.all(
      from b in __MODULE__,
        where: b.species_code in ^species_codes
    )
  end

  def get_many_by_species_code({:ok, %RegionSpeciesCodes.Response{codes: codes}}),
    do: {:ok, get_many_by_species_code(codes)}

  def get_many_by_species_code({:error, error}), do: {:error, error}

  def update(%__MODULE__{} = bird, attrs) do
    bird
    |> changeset(Enum.into(attrs, %{}))
    |> BirdSong.Repo.update()
  end

  @type repo_error() :: {:error, Changeset.t()}
  @type new_or_error() :: {:ok, t()} | repo_error()

  @spec from_raw(Map.t(), Family.t(), Order.t()) :: new_or_error()
  def from_raw(
        %{
          "sciName" => sci_name,
          "comName" => common_name,
          "speciesCode" => species_code,
          "category" => category,
          "taxonOrder" => taxon_order,
          "bandingCodes" => banding_codes,
          "comNameCodes" => common_name_codes,
          "sciNameCodes" => sci_name_codes
        } = raw,
        %Family{} = family,
        %Order{} = order
      ) do
    report_as = Map.get(raw, "reportAs")

    %__MODULE__{
      sci_name: sci_name,
      common_name: common_name,
      species_code: species_code,
      category: category,
      taxon_order: taxon_order,
      report_as: report_as,
      banding_codes: banding_codes,
      common_name_codes: common_name_codes,
      sci_name_codes: sci_name_codes,
      family: family,
      order: order
    }
    |> changeset()
    |> BirdSong.Repo.insert()
  end

  @doc false
  def changeset(%__MODULE__{} = bird, attrs \\ %{}) do
    bird
    |> cast(attrs, [:has_recordings?, :has_images? | @cast_keys])
    |> cast_assoc(:order)
    |> cast_assoc(:family)
    |> validate_required(@required_keys)
    |> unique_constraint(:species_code)
    |> unique_constraint(:common_name)
    |> unique_constraint(:sci_name)
    |> unique_constraint(:taxon_order)
  end

  def cast_keys() do
    @cast_keys
  end
end
