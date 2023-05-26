defmodule BirdSong.Services.Ebird.Taxonomy do
  require Logger
  alias Ecto.Multi

  alias BirdSong.{
    Bird,
    Family,
    Order,
    Services.Helpers
  }

  @callback params_from_raw(Map.t()) :: Map.t()
  @callback uid_raw_key() :: String.t()
  @callback uid_struct_key() :: Atom.t()

  def read_data_file(path \\ "data/taxonomy.json") do
    path
    |> Path.relative_to_cwd()
    |> File.read!()
    |> Jason.decode!()
  end

  def seed!(records, instance \\ BirdSong) when is_list(records) do
    {:ok, birds} =
      records
      |> seed(instance)
      |> BirdSong.Repo.transaction()

    Map.values(birds)
  end

  def seed(records, _instance \\ BirdSong) when is_list(records) do
    records = Enum.reject(records, &nil_family?/1)

    Multi.new()
    |> Multi.merge(&insert_parents(&1, {Order, :order}, records))
    |> Multi.merge(&insert_parents(&1, {Family, :family}, records))
    |> Multi.merge(&insert_birds(&1, records))
  end

  defp record_uid(record, schema) do
    Map.fetch!(record, schema.uid_raw_key())
  end

  defp insert_parents(changes, {module, key}, records) do
    params =
      records
      |> MapSet.new(&record_uid(&1, module))
      |> Enum.reduce(
        [],
        &prepare_parent_params(%{
          parent_name: &1,
          acc: &2,
          module: module,
          records: records,
          changes: changes
        })
      )

    Multi.new()
    |> Multi.insert_all(:"insert_all_#{key}", module, params)
    |> Multi.run(key, &parents_to_dict(&1, &2, module))
  end

  defp parents_to_dict(repo, %{}, module) do
    {:ok,
     module
     |> repo.all()
     |> Map.new(
       &{
         Map.fetch!(&1, module.uid_struct_key()),
         &1
       }
     )}
  end

  defp prepare_parent_params(%{
         parent_name: parent_name,
         acc: acc,
         module: module,
         records: records,
         changes: changes
       }) do
    records
    |> first_with_parent_uid(module, parent_name)
    |> add_params_to_list(%{acc: acc, module: module, changes: changes})
  end

  defp insert_birds(%{} = changes, records) do
    params =
      Enum.reduce(
        records,
        [],
        &add_params_to_list(&1, %{acc: &2, module: Bird, changes: changes})
      )

    Multi.new()
    |> Multi.insert_all(:birds, Bird, params)
  end

  defp nil_family?(%{} = record) do
    case Map.fetch(record, Family.uid_raw_key()) do
      {:ok, "" <> _} ->
        false

      :error ->
        log_nil_family(record)
        true
    end
  end

  defp first_with_parent_uid(records, parent_module, parent_name) do
    case Enum.find(
           records,
           &(record_uid(&1, parent_module) === parent_name)
         ) do
      %{} = record -> record
      nil -> raise "cannot find record with value #{parent_name} for #{inspect(parent_module)}"
    end
  end

  defp add_params_to_list(raw, %{acc: acc, module: module, changes: changes}) do
    [prepare_params(raw, module, changes) | acc]
  end

  defp prepare_params(raw, module, changes) do
    assoc_data = %{
      child_module: module,
      raw: raw,
      changes: changes
    }

    raw
    |> module.params_from_raw()
    |> get_assoc(:order, assoc_data)
    |> get_assoc(:family, assoc_data)
  end

  defp assoc_module(:family), do: Family
  defp assoc_module(:order), do: Order

  defp get_assoc(params, _, %{child_module: Order}) do
    # Order has no associations
    params
  end

  defp get_assoc(params, :family, %{child_module: Family}) do
    # Family has no family assoc
    params
  end

  defp get_assoc(params, assoc_name, %{raw: raw, changes: changes}) do
    # Family has Order assoc
    # Bird has Order and Family assoc

    Map.put(
      params,
      :"#{assoc_name}_id",
      get_assoc_id_from_changes(changes, assoc_name, raw)
    )
  end

  defp get_assoc_id_from_changes(changes, assoc_name, raw) do
    assoc_uid = Map.fetch!(raw, assoc_module(assoc_name).uid_raw_key())

    changes
    |> Map.fetch!(assoc_name)
    |> Map.fetch!(assoc_uid)
    |> Map.fetch!(:id)
  end

  defp log_nil_family(record) do
    Helpers.log(
      [
        taxonomy_parse_error: :nil_parents,
        common_name: record["comName"],
        sci_name: record["sciName"],
        family: record[Family.uid_raw_key()],
        order: record[Order.uid_raw_key()]
      ],
      __MODULE__,
      :debug
    )
  end
end
