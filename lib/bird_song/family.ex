defmodule BirdSong.Family do
  use Ecto.Schema
  alias Ecto.Changeset
  alias BirdSong.{Order, Bird}

  @keys [:code, :common_name, :order, :sci_name]

  schema "families" do
    field :common_name, :string
    field :code, :string
    field :sci_name, :string
    belongs_to :order, Order
    has_many :birds, Bird
  end

  def from_raw(
        %{
          "familyCode" => code,
          "familyComName" => common_name,
          "familySciName" => sci_name
        },
        %Order{} = order
      ) do
    BirdSong.Repo.insert(%__MODULE__{
      code: code,
      common_name: common_name,
      order: order,
      sci_name: sci_name
    })
  end

  def changeset(%__MODULE__{} = family, attrs \\ %{}) do
    family
    |> Changeset.cast(attrs, @keys)
    |> Changeset.validate_required(@keys)
    |> Changeset.unique_constraint([:sci_name, :species_code])
  end
end
