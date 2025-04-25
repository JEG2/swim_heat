defmodule SwimHeat.Parser.Strategy.OneEventAtATime do
  alias SwimHeat.Parser.State
  alias SwimHeat.Parser.State.Event
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
               (?:Y(?:ea)?r|Age)\s+
               (?:School|Team)\s+
               (?:(?<seed>Seed|Prelim)(?:\sTime)?)?\s*
               (?<type>Finals|Prelim)(?:\sTime)?\s*
               (?:Points)?\s*
               \z
             }x,
             line
           ) do
      type =
        cond do
          parsed["type"] == "Prelim" -> :prelim
          parsed["seed"] == "Prelim" and parsed["type"] == "Finals" -> :final
          true -> :only
        end

      %State{
        state
        | event: %Event{state.event | type: type},
          reading: :individual_swim
      }
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
               (?<seed>#{@time_pattern}|NT)?\s*
               (?<time>(?:[xX]|DQ\s+)?(?:#{@time_pattern}|NS|DQ|SCR|DNF|DFS))\s*
               (?<points>#{@points_pattern})?\s*
               (?<qualified>q)?\s*
               \z
             /x,
             line
           ) do
      State.add_swim(state, parsed)
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
               (?:(?<seed>Seed)(?:\sTime)?\s+)?
               (?<type>Finals)(?:\sTime)?\s*
               (?:Points)?\s*
               \z
             }x,
             line
           ) do
      type =
        cond do
          parsed["type"] == "Prelim" -> :prelim
          parsed["seed"] == "Prelim" and parsed["type"] == "Finals" -> :final
          true -> :only
        end

      %State{
        state
        | event: %Event{state.event | type: type},
          reading: :relay_swim
      }
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
               (?<seed>#{@time_pattern}|NT)?\s*
               (?<time>(?:[xX]|DQ\s+)?(?:#{@time_pattern}|NS|DQ|SCR|DNF|DFS))\s*
               (?<points>#{@points_pattern})?\s*
               (?<qualified>q)?\s*
               \z
             /x,
             line
           ) do
      State.add_swim(state, parsed)
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

      State.update_swim(state, fn [result | rest] ->
        swimmers = result.swimmers ++ swimmers
        [%Swim{result | swimmers: swimmers} | rest]
      end)
    else
      [] -> parse_splits(state, line)
    end
  end

  def parse_splits(state, line) do
    if String.match?(
         line,
         ~r/\A(?:\s+(?:#{@time_pattern}Q?(?:\s+\([^\)]*\))?|DQ))+\s*\z/x
       ) do
      State.update_swim(state, fn [swim | rest] ->
        [Swim.add_splits(swim, line) | rest]
      end)
    end
  end
end
