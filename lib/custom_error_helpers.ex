defmodule BirdSong.CustomError do
  def format(text) do
    IO.ANSI.format([
      :yellow,
      Enum.join(~w(#{text}), " ")
    ])
  end

  def format_with_space(error_text, module) do
    [
      "\n\n\n",
      format("Error: " <> to_string(module)),
      "\n\n",
      format(error_text),
      "\n\n\n"
    ]
    |> Enum.join("")
  end

  defmacro __using__(struct_keys) do
    quote bind_quoted: [struct_keys: struct_keys] do
      alias BirdSong.CustomError
      defexception struct_keys

      def message(struct) do
        struct
        |> message_text()
        |> CustomError.format_with_space(__MODULE__)
      end
    end
  end
end
