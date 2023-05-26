defmodule BirdSongWeb.QuizLiveTest do
  use BirdSongWeb.SupervisedLiveCase, path: "/quiz"
  import BirdSong.TestSetup, only: [seed_from_mock_taxonomy: 1]

  alias BirdSong.{
    Accounts,
    Bird,
    Quiz.Answer
  }

  alias BirdSongWeb.QuizLive.Current

  @moduletag load_view?: false

  setup [:seed_from_mock_taxonomy]

  setup tags do
    assert %{
             conn: conn,
             user: user,
             path_with_query: path
           } = Map.take(tags, [:conn, :user, :path_with_query])

    birds =
      Bird.get_many_by_common_name([
        "Carolina Wren",
        "Red-shouldered Hawk",
        "Common Grackle"
      ])

    assert [%Bird{}, %Bird{}, %Bird{}] = birds

    assert %{quiz: quiz, user: user} =
             Accounts.update_current_quiz!(user.id, %{region_code: "US-NC", birds: birds})

    assert {:ok, view, _html} = live(conn, path)

    {:ok, birds: birds, quiz: quiz, user: user, view: view}
  end

  test "shows possible bird buttons on connected mount", %{view: view, birds: birds} do
    assert has_element?(view, "button", "Change recording")

    for bird <- birds do
      assert has_element?(view, "button", bird.common_name)
    end
  end

  describe "correct answer" do
    @describetag to_click: :correct

    setup [:click_bird_button]

    test "saves answer and shows that the answer was correct", %{
      assigns: assigns,
      html: html,
      quiz: quiz
    } do
      assert %Current{
               bird: %Bird{id: id},
               answer: %Answer{submitted_bird: %Bird{id: id}, correct?: true}
             } = assigns.current

      assert html =~ "Correct!"

      assert [%Answer{id: answer_id}] = Answer.get_for_quiz(quiz.id)
      assert answer_id === assigns.current.answer.id
    end

    test "clicking next button loads the next bird", %{view: view} do
      view
      |> element("button", "Next")
      |> render_click()

      assigns = GenServer.call(view.pid, :socket).assigns
      assert assigns.current.answer === nil
    end
  end

  describe "incorrect_answer" do
    @describetag to_click: :incorrect
    setup [:click_bird_button]

    test "saves answer and shows that the answer was incorrect", %{
      assigns: assigns,
      clicked: clicked,
      html: html,
      quiz: quiz
    } do
      assert %Current{
               answer: %Answer{}
             } = assigns.current

      assert clicked.id !== assigns.current.bird.id
      assert assigns.current.answer.submitted_bird.id === clicked.id
      assert assigns.current.answer.correct? === false

      assert [%Answer{} = answer] =
               quiz.id
               |> Answer.get_for_quiz()
               |> BirdSong.Repo.preload([:submitted_bird])

      assert answer.id === assigns.current.answer.id

      assert Floki.text(html) =~
               "Your guess: " <> answer.submitted_bird.common_name

      assert Floki.text(html) =~ "Correct answer: " <> assigns.current.bird.common_name
    end

    test "clicking next button loads the next bird", %{view: view} do
      view
      |> element("button", "Next")
      |> render_click()

      assigns = GenServer.call(view.pid, :socket).assigns
      assert assigns.current.answer === nil
    end
  end

  defp click_bird_button(%{
         birds: birds,
         quiz: quiz,
         to_click: to_click,
         view: view
       }) do
    assigns = GenServer.call(view.pid, :socket).assigns
    assert %Bird{} = assigns.current.bird
    assert assigns.current.answer === nil
    assert Answer.get_for_quiz(quiz.id) === []

    bird =
      case to_click do
        :correct ->
          assigns.current.bird

        :incorrect ->
          Enum.find(birds, &(&1.id !== assigns.current.bird.id))
      end

    html =
      view
      |> element("button", bird.common_name)
      |> render_click()

    assigns = GenServer.call(view.pid, :socket).assigns
    {:ok, assigns: assigns, html: html, clicked: bird}
  end
end
