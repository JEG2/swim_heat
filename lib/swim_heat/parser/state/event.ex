defmodule SwimHeat.Parser.State.Event do
  alias SwimHeat.Database
  require Database

  defstruct [
    :number,
    :gender,
    :distance,
    :unit,
    :stroke,
    :relay,
    :type,
    records: %{}
  ]

  def new(fields) do
    number =
      case fields["number"] do
        "" -> nil
        n -> String.to_integer(n)
      end

    gender =
      case fields["gender"] do
        "Girls" -> :girls
        "Women" -> :girls
        "Boys" -> :boys
        "Men" -> :boys
        "Mixed" -> :mixed
      end

    unit =
      case fields["unit"] do
        "Yard" -> :yard
        "Meter" -> :meter
      end

    stroke =
      case fields["stroke"] do
        "Freestyle" -> :free
        "Free" -> :free
        "Breaststroke" -> :breast
        "Breast" -> :breast
        "Butterfly" -> :fly
        "Fly" -> :fly
        "Backstroke" -> :back
        "Back" -> :back
        "IM" -> :im
        "Medley" -> :medley
      end

    type =
      if fields["swim_off_short"] == "S" or
           fields["swim_off_long"] == "Swim-off" do
        :swim_off
      else
        nil
      end

    %__MODULE__{
      number: number,
      gender: gender,
      distance: String.to_integer(fields["distance"]),
      unit: unit,
      stroke: stroke,
      relay: fields["relay"] == "Relay",
      type: type
    }
  end

  def to_record(event) do
    if is_nil(event.type) do
      raise "Unset event type"
    end

    id =
      ~w[number gender distance unit stroke]a
      |> Enum.map_join(" ", fn f -> Map.fetch!(event, f) end)
      |> String.trim()

    id =
      if event.relay do
        "#{id} Relay"
      else
        id
      end

    Database.event(
      id: "#{id} #{event.type}",
      number: event.number,
      gender: event.gender,
      distance: event.distance,
      unit: event.unit,
      stroke: event.stroke,
      relay?: event.relay,
      type: event.type,
      records: event.records
    )
  end
end
