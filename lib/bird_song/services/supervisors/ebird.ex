defmodule BirdSong.Services.Supervisors.Ebird do
  use Supervisor

  alias BirdSong.Services.Helpers

  alias BirdSong.Services.{
    Ebird,
    RequestThrottler
  }

  @default_opts [
    parent_name: BirdSong.Services.Ebird,
    base_url: "https://api.ebird.org"
  ]

  @opt_keys [
    :base_url,
    :parent_name,
    :throttler
  ]

  def start_link(opts) do
    @default_opts
    |> Keyword.merge(opts)
    |> warn_unused_opts()
    |> do_start_link()
  end

  def init(opts) do
    Supervisor.init(
      [
        {RequestThrottler, throttler_opts(opts)},
        {Ebird.Regions.RegionETS, ets_opts(opts)},
        {Ebird.Observations, cache_opts(opts, :Observations)},
        {Ebird.RegionSpeciesCodes, cache_opts(opts, :RegionSpeciesCodes)},
        {Ebird.Regions, cache_opts(opts, :Regions)},
        {Ebird.RegionInfo, cache_opts(opts, :RegionInfo)}
      ],
      strategy: :one_for_one
    )
  end

  def child_name(opts, child_name) when is_list(child_name) do
    child_name(opts, Module.concat(child_name))
  end

  def child_name(opts, child_name) when is_atom(child_name) do
    opts
    |> Keyword.fetch!(:parent_name)
    |> Module.concat(child_name)
  end

  def get_child(child_module) when is_list(child_module) or is_atom(child_module) do
    get_child(child_module, BirdSong.Services)
  end

  def get_child(child_module, parent) when is_list(child_module) do
    child_module
    |> Module.concat()
    |> get_child(parent)
  end

  def get_child(child_module, parent) when is_atom(child_module) do
    parent
    |> children()
    |> Map.fetch!(child_module)
  end

  def children(parent \\ BirdSong.Services) do
    [parent_name: parent]
    |> child_name(:Supervisor)
    |> Supervisor.which_children()
    |> Enum.map(&child_to_map/1)
    |> Map.new()
  end

  defp child_opts(opts, child_name) when is_atom(child_name) or is_list(child_name) do
    opts
    |> Keyword.drop([:name, :parent_name])
    |> Keyword.put(:name, child_name(opts, child_name))
  end

  defp child_to_map({child_module, pid, :worker, [child_module]}) do
    {child_module, pid}
  end

  defp cache_opts(opts, child_name) do
    opts
    |> child_opts(child_name)
    |> Keyword.put(:throttler, child_name(opts, :Throttler))
  end

  defp do_start_link(opts) do
    Supervisor.start_link(
      __MODULE__,
      opts,
      name: child_name(opts, :Supervisor)
    )
  end

  defp ets_opts(opts) do
    opts
    |> child_opts([:Regions, :RegionETS])
    |> Keyword.take([:name])
  end

  defp throttler_opts(opts) do
    opts
    |> child_opts(:Throttler)
    |> Keyword.drop([:throttler, :parent_name])
  end

  defp warn_unused_opts(opts) do
    :ok = Enum.each(opts, &warn_if_unused_opt/1)
    opts
  end

  defp warn_if_unused_opt({key, _}) when key in @opt_keys do
    :ok
  end

  defp warn_if_unused_opt({key, _}) when key not in @opt_keys do
    Helpers.log([opt_key: key, message: "unused_option"], __MODULE__, :warning)
  end
end
