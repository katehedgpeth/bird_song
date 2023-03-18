defmodule Mix.Tasks.RecordData do
  require Logger

  @moduledoc "Seeds the database using data in data/taxonomy.json"
  @shortdoc "Seeds the database using data in data/taxonomy.json"

  @requirements ["app.config", "app.start"]

  alias BirdSong.{
    Bird,
    Family,
    Order,
    Services,
    Services.Ebird.Taxonomy,
    Services.Service,
    Services.XenoCanto,
    Services.Flickr
  }

  use Mix.Task

  defmodule Config do
    defstruct [
      :taxonomy_file,
      birds: [],
      services: nil,
      clear_db?: false,
      overwrite_files?: false,
      seed_taxonomy?: true
    ]

    def parse(args, services) do
      Enum.reduce(args, %__MODULE__{services: services}, &do_parse(&1, &2, services))
    end

    defp do_parse("--no-taxonomy", %__MODULE__{} = config, _services) do
      %{config | seed_taxonomy?: false}
    end

    defp do_parse("--taxonomy-file=" <> file, %__MODULE__{} = config, _services) do
      %{config | taxonomy_file: file}
    end

    defp do_parse("--overwrite", %__MODULE__{} = config, _services) do
      %{config | overwrite_files?: true}
    end

    defp do_parse("--bird=" <> common_name, %__MODULE__{} = config, _services) do
      bird = BirdSong.Repo.get_by!(Bird, common_name: String.replace(common_name, "_", " "))

      %{config | birds: [bird]}
    end

    defp do_parse("" <> arg, %__MODULE__{}, _services) do
      raise "unexpected argument: " <> arg
    end
  end

  def run(args, injected_services \\ Services.ensure_started()) do
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

  defp fetch_data_for_birds(%Config{
         birds: birds,
         services: %Services{} = services
       }) do
    birds
    |> Enum.map(&%{services | bird: &1})
    |> fetch_data_for_bird()
  end

  defp fetch_data_for_bird([]) do
    :ok
  end

  defp fetch_data_for_bird([
         %Services{bird: %Bird{} = bird, images: %Service{}, recordings: %Service{}} = current
         | rest
       ]) do
    responses = Services.fetch_data_for_bird(current)

    with {_,
          [
            images: {:ok, %Flickr.Response{}},
            recordings: {:ok, %XenoCanto.Response{}}
          ]} <-
           {bird.common_name,
            Enum.map(
              [:images, :recordings],
              &{&1,
               responses
               |> Map.fetch!(&1)
               |> Map.fetch!(:response)}
            )} do
      fetch_data_for_bird(rest)
    end
  end
end
