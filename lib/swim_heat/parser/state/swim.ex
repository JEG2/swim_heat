defmodule SwimHeat.Parser.State.Swim do
  defstruct [
    :place,
    :name,
    :year,
    :school,
    :seed,
    :time,
    :points,
    splits: [],
    swimmers: []
  ]

  def new(fields) do
    place =
      cond do
        String.match?(fields["place"], ~r{\A-+\z}) -> nil
        true -> String.to_integer(fields["place"])
      end

    points =
      case fields["points"] do
        nil -> nil
        "" -> nil
        n -> String.to_integer(n)
      end

    %__MODULE__{
      place: place,
      name: fields["name"] || "#{fields["school"]} #{fields["relay"]}",
      year: fields["year"],
      school: fields["school"],
      seed: parse_time(fields["seed"]),
      time: parse_time(fields["time"]),
      points: points
    }
  end

  def add_splits(swim, splits) do
    splits =
      splits
      |> String.trim()
      |> String.split()
      |> Enum.map(&parse_time/1)

    %__MODULE__{swim | splits: swim.splits ++ splits}
  end

  defp parse_time(nil), do: nil

  defp parse_time(time) do
    time = String.replace(time, ~r{\A[xX]}, "")

    cond do
      time in ~w[NT NS DQ] ->
        nil

      String.contains?(time, ":") ->
        [minutes, seconds] = String.split(time, ":", parts: 2)
        String.to_integer(minutes) * 60 + String.to_float(seconds)

      true ->
        String.to_float(time)
    end
  end
end
