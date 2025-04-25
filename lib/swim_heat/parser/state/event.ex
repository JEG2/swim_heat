defmodule SwimHeat.Parser.State.Event do
  defstruct ~w[number gender distance unit stroke relay type]a

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

    %__MODULE__{
      number: number,
      gender: gender,
      distance: String.to_integer(fields["distance"]),
      unit: unit,
      stroke: stroke,
      relay: fields["relay"] == "Relay"
    }
  end
end
