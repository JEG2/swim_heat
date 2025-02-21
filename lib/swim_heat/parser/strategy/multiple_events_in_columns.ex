defmodule SwimHeat.Parser.Strategy.MultipleEventsInColumns do
  alias SwimHeat.Parser.State
  alias SwimHeat.Parser.State.Meet
  alias SwimHeat.Parser.State.Swim

  @place_pattern "\\d+|-+"
  @name_pattern "\\S.*?"
  @year_pattern "FR|SO|JR|SR"
  @time_pattern "(?:\\d+:)?\\d+\\.\\d+"

  def parse_individual_headers(state, line) do
    with parsed when is_map(parsed) <-
           Regex.named_captures(
             ~r{
               \A\s*
               Name\s+
               Yr\s+
               Team\s+
               Finals\sTime\s*
               \z
             }x,
             line
           ) do
      %State{state | reading: :individual_swim}
    end
  end

  def parse_individual_swim(state, line) do
    with parsed when is_map(parsed) <-
           Regex.named_captures(
             ~r/
               \A\s*
               \*?(?<place>#{@place_pattern})\s+
               (?<name>#{@name_pattern})\s{2,}
               (?:(?<year>#{@year_pattern})\s+)?
               (?<school>#{@name_pattern})\s+
               (?<time>[xX]?(?:#{@time_pattern}|NS|DQ))\s*
               \z
             /x,
             line
           ) do
      add_swim(state, parsed)
    end
  end

  def parse_relay_headers(state, line) do
    with parsed when is_map(parsed) <-
           Regex.named_captures(
             ~r{
               \A\s*
               Team\s+
               Relay\s+
               Finals\sTime\s*
               \z
             }x,
             line
           ) do
      %State{state | reading: :relay_swim}
    end
  end

  def parse_relay_swim(state, line) do
    with parsed when is_map(parsed) <-
           Regex.named_captures(
             ~r/
               \A\s*
               \*?(?<place>#{@place_pattern})\s+
               (?<school>#{@name_pattern})\s+
               '?(?<relay>[A-E])'?\s+
               (?<time>[xX]?(?:#{@time_pattern}|NS|DQ))\s*
               \z
             /x,
             line
           ) do
      add_swim(state, parsed)
    else
      nil -> parse_swimmers(state, line)
    end
  end

  def parse_swimmers(state, line) do
    with matches when matches != [] <-
           Regex.scan(
             ~r/(\S.*?)\s(#{@year_pattern})?(?:\s{2,}|\s*\z)/,
             line,
             capture: :all_but_first
           ) do
      swimmers =
        matches
        |> Enum.map(&List.to_tuple/1)
        |> Enum.map(fn
          {_name, _year} = s -> s
          {name} -> {name, nil}
        end)

      %State{
        state
        | meet: %Meet{
            state.meet
            | events:
                Map.update!(
                  state.meet.events,
                  state.event,
                  fn [result | rest] ->
                    swimmers = result.swimmers ++ swimmers
                    [%Swim{result | swimmers: swimmers} | rest]
                  end
                )
          }
      }
    end
  end

  defp add_swim(state, fields) do
    swim = Swim.new(fields)

    %State{
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
end
