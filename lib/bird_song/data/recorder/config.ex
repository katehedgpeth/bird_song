defmodule BirdSong.Data.Recorder.Config do
  defstruct [
    :taxonomy_file,
    birds: [],
    services: nil,
    clear_db?: false,
    overwrite_files?: false,
    seed_taxonomy?: false
  ]

  def parse(args, services) do
    Enum.reduce(args, %__MODULE__{services: services}, &do_parse(&1, &2, services))
  end

  defp do_parse("--seed-taxonomy", %__MODULE__{} = config, _services) do
    %{config | seed_taxonomy?: true}
  end

  defp do_parse("--taxonomy-file=" <> file, %__MODULE__{} = config, _services) do
    %{config | seed_taxonomy?: true, taxonomy_file: file}
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
