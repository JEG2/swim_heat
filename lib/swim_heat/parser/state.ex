defmodule SwimHeat.Parser.State do
  alias SwimHeat.Parser.State.Meet
  alias SwimHeat.Parser.State.Swim

  defstruct page: 0,
            reading: nil,
            strategy: nil,
            meet: nil,
            event: nil,
            columns: nil,
            buffer: %{},
            fragment: nil

  def add_swim(state, fields) do
    swim = Swim.new(fields)

    %__MODULE__{
      state
      | meet: %Meet{
          state.meet
          | events:
              Map.update(
                state.meet.events,
                state.event,
                [swim],
                &[swim | &1]
              )
        }
    }
  end

  def update_swim(state, fun) do
    %__MODULE__{
      state
      | meet: %Meet{
          state.meet
          | events: Map.update!(state.meet.events, state.event, fun)
        }
    }
  end
end
