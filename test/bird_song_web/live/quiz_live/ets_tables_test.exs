defmodule BirdSongWeb.QuizLive.EtsTablesTest do
  use ExUnit.Case, async: true
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket
  alias BirdSongWeb.QuizLive.EtsTables

  describe "assign_tables/1" do
    test "assigns existing tables if they have not been assigned", %{} do
      %Socket{assigns: assigns} = EtsTables.assign_tables(%Socket{})
      assert_ets_tables_exist(assigns, EtsTables)
    end

    test "does not assign new tables if they are already assigned" do
      socket = LiveView.assign(%Socket{}, :ets_tables, %EtsTables{assigns: :NOT_REAL})
      assert EtsTables.assign_tables(socket) === socket
    end

    test "uses given module name when creating new tables" do
      %Socket{assigns: assigns} = EtsTables.assign_tables(%Socket{}, SomeModule)
      assert_ets_tables_exist(assigns, SomeModule)
    end
  end

  def assert_ets_tables_exist(socket_assigns, module) do
    assert %EtsTables{assigns: assigns_table} = Map.fetch!(socket_assigns, :ets_tables)
    assert is_reference(assigns_table)
    assert %EtsTables{assigns: ^assigns_table} = GenServer.call(module, :get_tables)
    assert :ets.info(assigns_table, :owner) === GenServer.whereis(module)
    assert :ets.info(assigns_table, :name) === Module.concat(module, Assigns)
  end
end
