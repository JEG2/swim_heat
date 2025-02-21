defmodule SwimHeat.Parser.State do
  defstruct page: 0,
            reading: nil,
            strategy: nil,
            meet: nil,
            event: nil,
            columns: nil,
            buffer: %{},
            fragment: nil
end
