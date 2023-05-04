defmodule BirdSong.CustomError do
  def format(text) do
    IO.ANSI.format([
      :yellow,
      Enum.join(~w(#{text}), " ")
    ])
  end

  defmacro __using__(struct_keys) do
    quote bind_quoted: [struct_keys: struct_keys] do
      alias BirdSong.CustomError
      defexception struct_keys

      def message(struct) do
        [
          "\n\n\n",
          CustomError.format("Error: " <> to_string(__MODULE__)),
          "\n\n",
          struct
          |> message_text()
          |> CustomError.format(),
          "\n\n\n"
        ]
        |> Enum.join("")
      end
    end
  end
end
