defmodule BirdSong.Services.Ebird.TaxonomyTest do
  use ExUnit.Case
  alias BirdSong.Services.Ebird.{Species, Taxonomy}

  test "&start_link/1 starts a server that populates an ets table" do
    name = :test_taxonomy_1
    assert {:ok, server} = Taxonomy.start_link(name: name)
    assert is_pid(server)
    assert %Taxonomy{ets_table: ets_table} = Taxonomy.state(name)
    assert ets_table |> :ets.info() |> Keyword.fetch!(:size) === 16860
  end

  test "&lookup/1 returns a species" do
    name = :test_taxonomy_2
    assert {:ok, server} = Taxonomy.start_link(name: name)

    assert {:ok, %Species{common_name: "Red-shouldered Hawk"}} =
             Taxonomy.lookup("Buteo lineatus", server)
  end
end
