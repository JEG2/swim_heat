defmodule SwimHeat.Parser.State.Record do
  defstruct [
    :time,
    :details,
    swimmers: []
  ]

  def new(time, details) do
    time =
      cond do
        String.contains?(time, ":") ->
          [minutes, seconds] = String.split(time, ":", parts: 2)
          String.to_integer(minutes) * 60 + String.to_float(seconds)

        true ->
          String.to_float(time)
      end

    %__MODULE__{
      time: time,
      details: details
    }
  end
end
