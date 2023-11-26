defmodule BirdSongWeb.Plugs.AssignQuizBird do
  alias Plug.Conn

  alias BirdSong.Bird
  alias BirdSong.Quiz

  @behaviour Plug

  @impl Plug
  def init([assign_to: key] = opts) when key in [:bird, :submitted_bird], do: opts

  @impl Plug
  def call(%Conn{method: method, params: %{"bird_id" => "random"}} = conn, _opts)
      when method != "GET" do
    conn
    |> Conn.put_status(:bad_request)
    |> Phoenix.Controller.json(%{
      message: "random id is only allowed on GET requests"
    })
    |> Conn.halt()
  end

  def call(
        %Conn{
          method: "GET",
          assigns: %{quiz: %Quiz{} = quiz},
          params: %{"bird_id" => "random"}
        } = conn,
        _opts
      ) do
    Conn.assign(
      conn,
      :bird,
      Enum.random(quiz.birds)
    )
  end

  def call(
        %Conn{
          assigns: %{quiz: %Quiz{} = quiz}
        } = conn,
        opts
      ) do
    assign_name = Keyword.fetch!(opts, :assign_to)
    bird_id = fetch_bird_id(conn.params, assign_name)

    case Enum.find(quiz.birds, &(&1.id === bird_id)) do
      %Bird{} = bird ->
        Conn.assign(conn, assign_name, bird)

      nil ->
        conn
        |> Conn.put_status(:bad_request)
        |> Phoenix.Controller.json(%{
          message: "Quiz #{quiz.id} does not include a bird with id #{bird_id}"
        })
        |> Conn.halt()
    end
  end

  defp fetch_bird_id(params, assign_name) do
    params
    |> Map.fetch!(param_name(assign_name))
    |> case do
      id when is_integer(id) ->
        id

      id when is_binary(id) ->
        {bird_id, ""} = Integer.parse(id, 10)
        bird_id
    end
  end

  defp param_name(assign_name) do
    assign_name |> Atom.to_string() |> Kernel.<>("_id")
  end
end
