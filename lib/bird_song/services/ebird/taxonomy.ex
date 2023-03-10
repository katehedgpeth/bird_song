defmodule BirdSong.Services.Ebird.Taxonomy do
  require Logger
  alias Ecto.Changeset
  alias BirdSong.{Bird, Family, Order, Services}

  def read_data_file(path \\ "data/taxonomy.json") do
    path
    |> Path.relative_to_cwd()
    |> File.read!()
    |> Jason.decode!()
  end

  @type seed_return() :: {:ok, [Services.t()]} | {:error, Changeset.t()}
  @type grouped_records_as_list() :: [{String.t(), [Map.t()]}]
  @type maybe_services() :: Services.t() | nil

  @spec seed([Map.t()]) :: seed_return()
  @spec seed([Map.t()], maybe_services()) :: seed_return()

  def seed(taxonomy, services \\ nil) when is_list(taxonomy) do
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
    |> parse_and_insert_order(services, [])
  end

  @spec parse_and_insert_order(grouped_records_as_list(), maybe_services(), [
          Services.TasksForBird.t()
        ]) ::
          seed_return()
  def parse_and_insert_order([], _services, tasks), do: {:ok, tasks}

  def parse_and_insert_order([{name, birds} | rest], services, tasks) do
    with {:ok, order} <- Order.insert(name),
         {:ok, tasks} <- parse_and_insert_families(birds, order, services, tasks) do
      parse_and_insert_order(rest, services, tasks)
    end
  end

  @spec parse_and_insert_families([Map.t()], Order.t(), maybe_services(), [
          Services.TasksForBird.t()
        ]) ::
          seed_return()
  def parse_and_insert_families(records, order, services, tasks) do
    records
    |> group_by_family()
    |> Map.to_list()
    |> parse_and_insert_family(order, services, tasks)
  end

  @spec parse_and_insert_family(grouped_records_as_list(), Order.t(), maybe_services(), [
          Services.TasksForBird.t()
        ]) ::
          seed_return()
  def parse_and_insert_family([], %Order{}, _services, tasks), do: {:ok, tasks}

  def parse_and_insert_family(
        [{_family_name, [_ | _] = birds} | rest],
        %Order{} = order,
        services,
        tasks
      ) do
    with {:ok, family} <- birds |> List.first() |> Family.from_raw(order),
         {:ok, tasks} <-
           parse_and_insert_bird(birds, family, order, services, tasks) do
      parse_and_insert_family(rest, order, services, tasks)
    end
  end

  @spec parse_and_insert_bird([Map.t()], Family.t(), Order.t(), maybe_services(), [
          Services.t()
        ]) ::
          seed_return()
  defp parse_and_insert_bird([], %Family{}, %Order{}, _services, tasks) do
    {:ok, tasks}
  end

  defp parse_and_insert_bird(
         [%{} = bird | rest],
         %Family{} = family,
         %Order{} = order,
         services,
         tasks
       ) do
    with {{:ok, %Bird{} = bird}, :bird} <-
           {Bird.from_raw(bird, family, order), :bird} do
      new_tasks =
        case services do
          nil -> %Services{bird: bird}
          %Services{} -> Services.fetch_data_for_bird(%{services | bird: bird})
        end

      parse_and_insert_bird(rest, family, order, services, [new_tasks | tasks])
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
