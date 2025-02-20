defmodule SwimHeat.Parser.State.Meet do
  defstruct start_date: nil, name: nil, events: %{}

  def new(fields) do
    %__MODULE__{
      start_date:
        Date.new!(
          String.to_integer(fields["year"]),
          String.to_integer(fields["month"]),
          String.to_integer(fields["day"])
        ),
      name: fields["name"]
    }
  end
end
