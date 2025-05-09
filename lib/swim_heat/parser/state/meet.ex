defmodule SwimHeat.Parser.State.Meet do
  alias SwimHeat.Database
  require Database

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

  def to_record(meet) do
    Database.meet(
      id: "#{Date.to_iso8601(meet.start_date)} #{meet.name}",
      start_date: meet.start_date,
      name: meet.name
    )
  end
end
