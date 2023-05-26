defmodule BirdSong.Order do
  use Ecto.Schema
  alias Ecto.Changeset

  alias BirdSong.{
    Family,
    Bird,
    Services.Ebird.Taxonomy
  }

  @behaviour Taxonomy

  schema "orders" do
    field :name, :string
    has_many :families, Family
    has_many :birds, Bird
  end

  @impl Taxonomy
  def uid_raw_key(), do: "order"

  @impl Taxonomy
  def uid_struct_key(), do: :name

  @impl Taxonomy
  def params_from_raw(%{"order" => name}) do
    %{name: name}
  end

  def changeset(%__MODULE__{} = order, %{} = attrs \\ %{}) do
    order
    |> Changeset.cast(attrs, [:name])
    |> Changeset.validate_required([:name])
    |> Changeset.unique_constraint([:name])
  end

  def insert("" <> name) do
    %__MODULE__{name: name}
    |> changeset()
    |> BirdSong.Repo.insert()
  end
end
