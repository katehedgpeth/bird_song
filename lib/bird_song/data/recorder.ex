defmodule BirdSong.Data.Recorder do
  require Logger

  @moduledoc "Fetches data for any birds that exist in the database but do not have recordings or images."

  alias BirdSong.Services.Helpers

  alias BirdSong.{
    Bird,
    Family,
    Order,
    Services,
    Services.Ebird.Taxonomy,
    Services.Service
  }

  alias __MODULE__.Config

  def record(args, injected_services \\ Services.ensure_started()) do
    config = Config.parse(args, injected_services)

    setup(config)

    config
    |> get_birds_to_fetch()
    |> fetch_data_for_birds()
  end

  def setup(%Config{} = config) do
    :ok = update_write_configs(config)
    maybe_seed_taxonomy(config)
  end

  defp maybe_seed_taxonomy(%Config{seed_taxonomy?: false}) do
    {:ok, []}
  end

  defp maybe_seed_taxonomy(%Config{seed_taxonomy?: true} = config) do
    BirdSong.Repo.delete_all(Bird)
    BirdSong.Repo.delete_all(Family)
    BirdSong.Repo.delete_all(Order)

    config
    |> read_taxonomy_file()
    |> Taxonomy.seed()
  end

  defp read_taxonomy_file(%Config{taxonomy_file: nil}) do
    Taxonomy.read_data_file()
  end

  defp read_taxonomy_file(%Config{taxonomy_file: "" <> path}) do
    Taxonomy.read_data_file(path)
  end

  defp update_write_configs(%Config{
         services: %Services{images: images, recordings: recordings}
       }) do
    Enum.each([images, recordings], &update_write_config/1)
  end

  defp update_write_config(%Service{whereis: whereis}) do
    GenServer.cast(whereis, {:update_write_config, true})
  end

  defp get_birds_to_fetch(%Config{birds: [%Bird{} | _]} = config) do
    config
  end

  defp get_birds_to_fetch(%Config{birds: []} = config) do
    %{config | birds: BirdSong.Repo.all(Bird)}
  end

  defp elapsed_seconds(%DateTime{} = start_time) do
    DateTime.diff(now(), start_time)
  end

  defp fetch_data_for_birds(%Config{
         birds: birds,
         services: %Services{} = services
       }) do
    birds
    |> Enum.map(&%{services | bird: &1})
    |> fetch_data_for_bird({now(), length(birds)})
  end

  defp fetch_data_for_bird([], _) do
    :ok
  end

  defp fetch_data_for_bird(
         [
           %Services{bird: %Bird{} = bird, images: %Service{}, recordings: %Service{}} = current
           | rest
         ],
         {%DateTime{} = start_time, initial_count}
       ) do
    Helpers.log(
      [
        elapsed_seconds: elapsed_seconds(start_time),
        collected: initial_count - (length(rest) + 1)
      ],
      __MODULE__,
      :warning
    )

    responses = Services.fetch_data_for_bird(current)

    run_again = fn -> fetch_data_for_bird(rest, {start_time, initial_count}) end

    try do
      case {bird.common_name,
            Enum.map(
              [:images, :recordings],
              &{&1,
               responses
               |> Map.fetch!(&1)
               |> Map.fetch!(:response)}
            )} do
        {_, [images: {:ok, %{}}, recordings: {:ok, %{}}]} ->
          run_again.()

        {_, [images: {:ok, %{}}, recordings: {:error, {:no_results, _}}]} ->
          run_again.()

        {_, [images: {:error, {:no_results, _}}, recordings: {:ok, %{}}]} ->
          run_again.()
      end
    catch
      error ->
        {_, pid} = GenServer.call(current.recordings.whereis, :scraper_info)
        GenServer.stop(pid)

        Helpers.log(
          [
            message: "exited_before_finish",
            last_bird: bird,
            elapsed_seconds: elapsed_seconds(start_time)
          ],
          __MODULE__,
          :warning
        )

        raise error
    end
  end

  defp now(), do: DateTime.now!("Etc/UTC")
end
