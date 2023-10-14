defmodule BirdSong.Family do
  use Ecto.Schema
  alias Ecto.Changeset

  alias BirdSong.{
    Bird,
    Order,
    Services.Ebird.Taxonomy
  }

  @behaviour Taxonomy

  @derive {Jason.Encoder, only: [:code, :common_name, :sci_name]}

  @keys [:code, :common_name, :order, :sci_name]

  @type name() :: String.t()

  schema "families" do
    field(:common_name, :string)
    field(:code, :string)
    field(:sci_name, :string)
    belongs_to(:order, Order)
    has_many(:birds, Bird)
  end

  @impl Taxonomy
  def uid_struct_key(), do: :code

  @impl Taxonomy
  def uid_raw_key(), do: "familyCode"

  @impl Taxonomy
  def params_from_raw(%{
        "familyCode" => code,
        "familyComName" => common_name,
        "familySciName" => sci_name
      }) do
    %{
      code: code,
      common_name: common_name,
      sci_name: sci_name
    }
  end

  def changeset(%__MODULE__{} = family, attrs \\ %{}) do
    family
    |> Changeset.cast(attrs, @keys)
    |> Changeset.validate_required(@keys)
    |> Changeset.unique_constraint([:sci_name, :species_code])
  end
end
