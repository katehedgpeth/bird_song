defmodule BirdSong.Services.Ebird.Taxonomy do
  require Logger
  alias Ecto.Changeset

  alias BirdSong.{
    Bird,
    Family,
    Order
  }

  def read_data_file(path \\ "data/taxonomy.json") do
    path
    |> Path.relative_to_cwd()
    |> File.read!()
    |> Jason.decode!()
  end

  @type seed_return() :: {:ok, [Bird.t()]} | {:error, Changeset.t()}
  @type grouped_records_as_list() :: [{String.t(), [Map.t()]}]

  @spec seed([Map.t()]) :: seed_return()

  def seed(taxonomy) when is_list(taxonomy) do
    {no_family, with_family} = Enum.split_with(taxonomy, &(&1["familyCode"] === nil))

    Enum.map(
      no_family,
      &Logger.warning(
        taxonomy_parse_error: :no_family,
        common_name: &1["comName"],
        sci_name: &1["sciName"]
      )
    )

    with_family
    |> group_by_order()
    |> Map.to_list()
    |> parse_and_insert_order([])
  end

  @spec parse_and_insert_order(grouped_records_as_list(), [Bird.t()]) ::
          seed_return()
  def parse_and_insert_order([], birds), do: {:ok, birds}

  def parse_and_insert_order([{name, order_birds} | rest], all_birds) do
    with {:ok, order} <- Order.insert(name),
         {:ok, all_birds} <- parse_and_insert_families(order_birds, order, all_birds) do
      parse_and_insert_order(rest, all_birds)
    end
  end

  @spec parse_and_insert_families([Map.t()], Order.t(), [Bird.t()]) ::
          seed_return()
  def parse_and_insert_families(records, order, all_birds) do
    records
    |> group_by_family()
    |> Map.to_list()
    |> parse_and_insert_family(order, all_birds)
  end

  @spec parse_and_insert_family(grouped_records_as_list(), Order.t(), [Bird.t()]) ::
          seed_return()
  def parse_and_insert_family([], %Order{}, all_birds), do: {:ok, all_birds}

  def parse_and_insert_family(
        [{_family_name, [_ | _] = family_birds} | rest],
        %Order{} = order,
        all_birds
      ) do
    with {:ok, family} <-
           family_birds
           |> List.first()
           |> Family.from_raw(order),
         {:ok, all_birds} <-
           parse_and_insert_bird(family_birds, family, order, all_birds) do
      parse_and_insert_family(rest, order, all_birds)
    end
  end

  @spec parse_and_insert_bird([Map.t()], Family.t(), Order.t(), [Bird.t()]) ::
          seed_return()
  defp parse_and_insert_bird([], %Family{}, %Order{}, all_birds) do
    {:ok, all_birds}
  end

  defp parse_and_insert_bird(
         [%{} = bird | rest],
         %Family{} = family,
         %Order{} = order,
         all_birds
       ) do
    with {:ok, %Bird{} = new_bird} <- Bird.from_raw(bird, family, order) do
      parse_and_insert_bird(rest, family, order, [new_bird | all_birds])
    end
  end

  def group_by_family(list) do
    Enum.group_by(list, &family_name/1)
  end

  def group_by_order(list) do
    Enum.group_by(list, &order_name/1)
  end

  def family_name(%{"familyCode" => family_name}), do: family_name
  def order_name(%{"order" => order_name}), do: order_name
  def common_name(%{"comName" => common_name}), do: common_name
end
