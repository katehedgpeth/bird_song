defmodule BirdSong.Services.InjectableChildSpecs do
  alias BirdSong.{
    Services,
    Services.DataFile
  }

  def child_specs(opts) when is_list(opts) do
    # Services do not take options outside of the test environment.
    if Mix.env() !== :test do
      raise RuntimeError.exception("Do not pass options to Services outside of tests")
    end

    # :env can be included in the child options
    # to ensure that a test uses production specs
    opts
    |> Keyword.pop(:env, Mix.env())
    |> child_specs()
  end

  def child_specs({:test, opts}) when is_list(opts) do
    [DataFile | Keyword.get(opts, :service_modules, Services.child_modules())]
    |> Enum.uniq()
    |> Enum.map(&child_spec(&1, opts, :test))
  end

  def child_specs({_env, _opts}) do
    Services.child_specs!()
  end

  defp child_spec(DataFile, opts, :test) do
    {DataFile,
     Keyword.merge(
       [
         parent_folder: Keyword.get(opts, :parent_data_folder, "data"),
         overwrite?: Keyword.get(opts, :overwrite_data?, false),
         name: child_instance_name(opts, DataFile)
       ],
       Keyword.get(opts, DataFile, [])
     )}
  end

  defp child_spec(module, opts, :test) do
    {module,
     opts
     |> put_test_overrides(module, Keyword.get(opts, module, []))
     |> Keyword.drop([:name, :base_urls])}
  end

  def child_instance_name(opts, service) when is_list(opts) do
    opts
    |> supervisor_instance_name()
    |> Services.service_instance_name(service)
  end

  def supervisor_instance_name(opts) do
    Keyword.get(opts, :name, Services)
  end

  defp put_test_overrides(opts, module, custom_service_opts)
       when is_atom(module) and
              is_list(opts) and
              is_list(custom_service_opts) do
    opts
    |> Keyword.take([:allow_external_calls?, :throttle_ms])
    |> put_test_url(module, opts)
    |> Keyword.merge(custom_service_opts)
    |> Keyword.put(:service_name, child_instance_name(opts, module))
  end

  @spec put_test_url(Keyword.t(), module(), Keyword.t()) :: Keyword.t()
  defp put_test_url(service_opts, module, opts) do
    opts
    |> Keyword.get(:base_urls, [])
    |> Keyword.get(module)
    |> case do
      nil -> service_opts
      "" <> _ = base_url -> Keyword.put(service_opts, :base_url, base_url)
    end
  end
end
