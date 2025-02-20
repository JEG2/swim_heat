defmodule SwimHeat.Parser.Strategy.OneEventAtATime do
  alias SwimHeat.Parser.State
  alias SwimHeat.Parser.State.Meet
  alias SwimHeat.Parser.State.Swim

  @place_pattern "\\d+|-+"
  @name_pattern "\\S.*?"
  @year_pattern "FR|SO|JR|SR|\\d+"
  @time_pattern "(?:\\d+:)?\\d+\\.\\d+"
  @points_pattern "\\d+"

  def parse_individual_headers(state, line) do
    with parsed when is_map(parsed) <-
           Regex.named_captures(
             ~r{
               \A\s*
               Name\s+
               (?:Yr|Age)\s+
               School\s+
               Seed(?:\sTime)?\s+
               Finals(?:\sTime)?\s+
               Points\s*
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
               (?<place>#{@place_pattern})\s+
               (?<name>#{@name_pattern})\s+
               (?:(?<year>#{@year_pattern})\s+)?
               (?<school>#{@name_pattern})\s+
               (?<seed>#{@time_pattern}|NT)\s+
               (?<time>[xX]?(?:#{@time_pattern}|NS|DQ))\s*
               (?<points>#{@points_pattern})?\s*
               \z
             /x,
             line
           ) do
      add_swim(state, parsed)
    else
      nil -> parse_splits(state, line)
    end
  end

  def parse_relay_headers(state, line) do
    with parsed when is_map(parsed) <-
           Regex.named_captures(
             ~r{
               \A\s*
               (?:Team|School)\s+
               (?:Relay\s+)?
               Seed(?:\sTime)?\s+
               Finals(?:\sTime)?\s+
               Points\s*
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
               (?<place>#{@place_pattern})\s+
               (?<school>#{@name_pattern})\s+
               '?(?<relay>[A-E])'?\s+
               (?<seed>#{@time_pattern}|NT)\s+
               (?<time>[xX]?(?:#{@time_pattern}|NS|DQ))\s*
               (?<points>#{@points_pattern})?\s*
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
             ~r/[1-4]\)\s+(\S\D*?)\s+(#{@year_pattern})?(?=\s+[1-4]\)|\s*\z)/,
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
    else
      [] -> parse_splits(state, line)
    end
  end

  def parse_splits(state, line) do
    if String.match?(line, ~r/\A(?:\s+(?:#{@time_pattern}|DQ))+\s*\z/) do
      %State{
        state
        | meet: %Meet{
            state.meet
            | events:
                Map.update!(
                  state.meet.events,
                  state.event,
                  fn [swim | rest] ->
                    [Swim.add_splits(swim, line) | rest]
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
