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
      |> String.replace(~r{\(\s+\)}, "()")
      |> String.split()
      |> Enum.reject(fn t -> String.starts_with?(t, "(") end)
      |> Enum.map(&parse_time/1)

    %__MODULE__{swim | splits: swim.splits ++ splits}
  end

  defp parse_time(nil), do: nil

  defp parse_time(time) do
    time =
      time
      |> String.replace(~r{\A[xX]}, "")
      |> String.replace(~r{(\d)Q\z}, "\\1")

    cond do
      String.starts_with?(time, "DQ") or time in ~w[NT NS SCR DNF] ->
        nil

      String.contains?(time, ":") ->
        [minutes, seconds] = String.split(time, ":", parts: 2)
        String.to_integer(minutes) * 60 + String.to_float(seconds)

      true ->
        String.to_float(time)
    end
  end
end
