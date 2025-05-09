defmodule SwimHeat.Parser.State.Swim do
  alias SwimHeat.Database
  require Database

  defstruct [
    :place,
    :name,
    :year,
    :school,
    :seed,
    :time,
    :points,
    :dq?,
    :dq_reason,
    :qualified?,
    splits: [],
    swimmers: []
  ]

  def new(fields) do
    place =
      cond do
        String.match?(fields["place"], ~r{\A-+\z}) -> nil
        true -> String.to_integer(fields["place"])
      end

    name =
      cond do
        is_nil(fields["name"]) ->
          nil

        fields["name"] == "Rosa-Barrios, Zachary F" ->
          "Rosa-Berrios, Zachary"

        String.contains?(fields["name"], ",") and
            String.match?(fields["name"], ~r{\s[A-Z]\z}) ->
          String.slice(fields["name"], 0..-3//1)

        true ->
          fields["name"]
      end

    school =
      fields["school"]
      |> String.replace(~r{-OK\z}, "")
      |> normalize_school()

    points =
      case fields["points"] do
        nil ->
          nil

        "" ->
          nil

        n ->
          n =
            if String.contains?(n, ".") do
              n
            else
              "#{n}.0"
            end

          String.to_float(n)
      end

    %__MODULE__{
      place: place,
      name: name || "#{fields["school"]} #{fields["relay"]}",
      year: fields["year"],
      school: school,
      seed: parse_time(fields["seed"]),
      time: parse_time(fields["time"]),
      points: points,
      dq?: is_nil(place),
      qualified?: fields["qualified"] == "q"
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
  defp parse_time(""), do: nil

  defp parse_time(time) do
    time =
      time
      |> String.replace(~r{\A[xX]}, "")
      |> String.replace(~r{(\d)[^\d\s]\z}, "\\1")

    cond do
      String.starts_with?(time, "DQ") or time in ~w[NT NS SCR DNF DFS] ->
        nil

      String.contains?(time, ":") ->
        [minutes, seconds] = String.split(time, ":", parts: 2)
        String.to_integer(minutes) * 60 + String.to_float(seconds)

      true ->
        String.to_float(time)
    end
  end

  def to_swimmer_record(swim) do
    id = String.trim("#{swim.name} #{swim.school}")

    Database.swimmer(
      id: id,
      name: swim.name,
      year: swim.year,
      school: swim.school
    )
  end

  def to_swim_record(id, swim) do
    Database.swim(
      id: id,
      place: swim.place,
      seed: swim.seed,
      time: swim.time,
      points: swim.points,
      dq?: swim.dq?,
      dq_reason: swim.dq_reason,
      qualified?: swim.qualified?,
      splits: swim.splits,
      swimmers: swim.swimmers
    )
  end

  def normalize_school("ALTUS"), do: "Altus Bulldogs"
  def normalize_school("BA"), do: "Broken Arrow High School"
  def normalize_school("Broken Arrow Swim Team"), do: "Broken Arrow High School"
  def normalize_school("BART"), do: "Bartlesville High School"
  def normalize_school("BETH"), do: "Bethany High School"
  def normalize_school("BIXBY"), do: "Bixby High School"
  def normalize_school("BK"), do: "Bishop Kelley High School Swim"
  def normalize_school("BTW"), do: "Booker T Washington"
  def normalize_school("CAHS"), do: "Carl Albert High School"
  def normalize_school("CHS"), do: "Claremore High School"
  def normalize_school("Claremore"), do: "Claremore High School"
  def normalize_school("CSAS"), do: "Classen Sas"
  def normalize_school("Classen Sas Swim Team"), do: "Classen Sas"
  def normalize_school("Casady School Swim Team"), do: "Casady"
  def normalize_school("DCHS"), do: "Deer Creek High School"
  def normalize_school("DUN"), do: "Duncan High School"
  def normalize_school("Duncan"), do: "Duncan High School"
  def normalize_school("EDISO"), do: "Edison Preparatory High School"
  def normalize_school("EPHS"), do: "Edison Preparatory High School"
  def normalize_school("ELGIN"), do: "Elgin High School Swim"
  def normalize_school("EHS"), do: "Elgin High School Swim"
  def normalize_school("Elgin Owls"), do: "Elgin High School Swim"
  def normalize_school("ENID"), do: "Enid High School"
  def normalize_school("L-EHS"), do: "Eisenhower High School"
  def normalize_school("SF"), do: "Edmond Santa Fe"
  def normalize_school("NORTH"), do: "Edmond North"
  def normalize_school("FG"), do: "Fort Gibson Tigers"
  def normalize_school("GHS"), do: "Guymon High School"
  def normalize_school("HAR"), do: "Harrah High School"
  def normalize_school("HARRA"), do: "Harrah High School"
  def normalize_school("HCP"), do: "Harding Charter Prep"
  def normalize_school("Haas Hall Academy - Springdale-AR"), do: "Haas Hall Academy-AR"
  def normalize_school("JHS-HS"), do: "Jenks High School Swim Team"
  def normalize_school("Jenks High School Swim Team-HS"), do: "Jenks High School Swim Team"
  def normalize_school("LPS"), do: "Lawton Public Schools"
  def normalize_school("MEMO"), do: "Edmond Memorial"
  def normalize_school("MAC"), do: "MacArthur High School"
  def normalize_school("MAR"), do: "Marlow"
  def normalize_school("Marlow HS"), do: "Marlow"
  def normalize_school("MCG"), do: "Bishop McGuiness High School"
  def normalize_school("MHS"), do: "Muskogee High School Swim Team"
  def normalize_school("MSM"), do: "Mount Saint Mary"
  def normalize_school("MWCHS"), do: "Midwest City High School"
  def normalize_school("Mustang High School"), do: "Mustang"
  def normalize_school("NEWC"), do: "Newcastle High School"
  def normalize_school("NOR"), do: "Norman High School"
  def normalize_school("NN"), do: "Norman North High School"
  def normalize_school("OOLO"), do: "Oologah-Talala"
  def normalize_school("OWA"), do: "Owasso"
  def normalize_school("Owa"), do: "Owasso"
  def normalize_school("PC"), do: "Putnam City High School"
  def normalize_school("PCHS"), do: "Putnam City High School"
  def normalize_school("PCN"), do: "Putnam City North"
  def normalize_school("PCW"), do: "Putnam City West Swim Team"
  def normalize_school("PLV"), do: "Plainview High School Indians"
  def normalize_school("PRYOR-US"), do: "Pryor Swim-US"
  def normalize_school("Pampa High School"), do: "Pampa"
  def normalize_school("Piedmont High School"), do: "Piedmont"
  def normalize_school("SHAW"), do: "Shawnee High School"
  def normalize_school("STILL"), do: "Stillwater High School"
  def normalize_school("Storm"), do: "Storm Home Schooling Team"
  def normalize_school("UNION"), do: "Union High School"
  def normalize_school("WF Legacy"), do: "Wichita Falls Legacy"
  def normalize_school("WF Memorial"), do: "Wichita Falls Memorial"
  def normalize_school("Yukon High School"), do: "Yukon"
  def normalize_school(school), do: school
end
