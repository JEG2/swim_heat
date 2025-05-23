defmodule SwimHeat.Parser do
  alias SwimHeat.Parser.State
  alias SwimHeat.Parser.State.Event
  alias SwimHeat.Parser.State.Meet
  alias SwimHeat.Parser.State.Swim
  alias SwimHeat.Parser.Strategy.OneEventAtATime
  alias SwimHeat.Parser.Strategy.MultipleEventsInColumns
  alias SwimHeat.PrivFiles

  @event_pattern """
    (?:
      (?:
        (?:[AB]\\s+-\\s+Final|Preliminaries)
        \\s+\\.\\.\\.\\s+
      )?
      \\(
    )?
    (?:
      (?:Event\\s+|\\#)
      (?<number>\\d+)
      (?<swim_off_short>S)?\\s+
    )?
    (?<gender>Girls|Boys|Women|Men|Mixed)\\s+
    (?<distance>\\d+)\\s+
    (?:SC\\s+)?(?<unit>Yard|Meter)\\s+
    (?<stroke>
      Free(?:style)?|
      (?:Back|Breast)(?:stroke)?|
      Butterfly|
      Fly|
      IM|
      Medley
    )\\s*
    (?<relay>Relay)?\\s*
    (?<swim_off_long>Swim-off)?
    \\)?
  """
  @event_re ~r{\A\s*#{@event_pattern}\s*}x
  @event_type_re ~r{\A\s*(?:[ABC]\s+-\s+Final|Preliminaries|-\s+Swim-off)\s*\z}

  def stream_meets do
    PrivFiles.all_txts()
    |> Stream.reject(&skipped_file?/1)
    |> Stream.map(fn file -> parse_meet(file) end)
  end

  def skipped_file?(file) do
    String.ends_with?(file, "2024-11-12_union_multi_dual_meet.txt")
  end

  def parse_meet(file) do
    lines =
      file
      |> File.stream!()
      |> Stream.map(&apply_fixes/1)

    state = choose_strategy(lines)
    process_stream(lines, file, state)
  end

  def apply_fixes(line) do
    line
    |> String.replace("Butter ly", "Butterfly")
    |> String.replace("Butte2/17/2018", "Butterfly")
    |> String.replace(
      ~r{(Bishop\sKelley\sHigh\sSchool\sSwim-O)(\d)},
      "\\1K    \\2"
    )
    |> String.replace(
      ~r{(Muskogee\sHigh\sSchool\sSwim\sTeam)(\d)},
      "\\1    \\2"
    )
    |> String.replace(
      ~r{
        \A(\s+1\s+Cermak,\s+Lucy\s+O\s+FR\s+)
        (\s+1:00.14\s+1:00.20\s+20\s*)\z
      }x,
      "\\1    \\2"
    )
    |> String.replace(
      ~r{
        \A(\s+8\s+Schott,\s+Holden\s+A\s+JR\s+)
        (\s+1:11.57\s+1:16.15\s+11\s*)\z
      }x,
      "\\1    \\2"
    )
    |> String.replace(
      ~r{
        \A(\s+---\s+Peaster,\s+Natalie\s+FR\s+)
        (\s+1:54.58\s+DQ\s+1:56.34\s*)\z
      }x,
      "\\1    \\2"
    )
    |> String.replace(
      ~r{
        \A(\s+2\s+Warden,\s+Marcus\s+S\s+SO\s+)
        (\s+1:16.53\s+1:16.54\s+17\s*)\z
      }x,
      "\\1    \\2"
    )
    |> String.replace(
      ~r{(De\sLa\sTorre\sJimenez,\sVioleta\s)(15\sENID-OK)},
      "\\1 \\2"
    )
  end

  def choose_strategy(enum) do
    columns =
      Enum.reduce(enum, MapSet.new(), fn line, acc ->
        Regex.scan(
          ~r{#{@event_pattern}}x,
          line,
          return: :index,
          capture: :first
        )
        |> Enum.reduce(acc, fn [{i, _len}], acc ->
          MapSet.put(acc, i)
        end)
      end)
      |> Enum.sort()
      |> Enum.reduce([0], fn i, [prev | _rest] = acc ->
        if i - prev > 10 do
          [i | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()

    case columns do
      [0] ->
        %State{strategy: OneEventAtATime}

      starts ->
        ranges =
          (starts ++ [0])
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [i, len] -> i..(len - 1)//1 end)

        %State{strategy: MultipleEventsInColumns, columns: ranges}
    end
  end

  defp process_stream(enum, file, state) do
    result =
      Enum.reduce_while(enum, state, fn line, state ->
        try do
          case parse_line(state, line) do
            %State{reading: :done} = s -> {:halt, s}
            %State{} = s -> {:cont, s}
            {:error, message} -> {:halt, {:error, message, file, line}}
            nil -> {:halt, {:error, "#{state.reading} not found", file, line}}
          end
        rescue
          error ->
            IO.inspect(__STACKTRACE__)
            {:halt, {:error, error, file, line}}
        end
      end)

    case result do
      state when is_struct(state, State) ->
        if is_map(state.buffer) and map_size(state.buffer) > 0 do
          state.buffer
          |> Enum.sort()
          |> Enum.flat_map(fn {_i, lines} -> Enum.reverse(lines) end)
          |> process_stream(
            file,
            %State{state | columns: [0..-1//1], buffer: nil, reading: :event}
          )
        else
          if state.reading not in ~w[individual_swim relay_swim done]a do
            IO.inspect(state)
            raise "Unfinished parsing:  #{file}"
          end

          post_process(state.meet)
        end

      error ->
        error
    end
  end

  def parse_line(state, line) do
    # IO.inspect({state.strategy, state.reading, line})

    cond do
      is_binary(state.fragment) ->
        with merged when is_binary(merged) <-
               merge_lines(state.fragment, line) do
          parse_line(%State{state | fragment: nil}, apply_fixes(merged))
        end

      finished?(line) and not buffering?(state) ->
        %State{state | reading: :done}

      page_start?(line) ->
        %State{state | page: state.page + 1, reading: :meet_name_and_date}

      junk_line?(line) ->
        state

      state.reading in ~w[meet_name_and_date results prelim_dupes]a ->
        apply(__MODULE__, :"parse_#{state.reading}", [state, line])

      buffering?(state) ->
        %State{state | buffer: extract_columns(state, line)}

      new_event?(state, line) ->
        parse_event(%State{state | reading: :event}, line)

      event_type?(state, line) ->
        if String.contains?(line, "Final") and state.event.type != :final do
          raise "Mismatched event types"
        end

        if String.contains?(line, "Swim-off") and
             state.event.type != :swim_off do
          raise "Mismatched event types"
        end

        if String.contains?(line, "Preliminaries") and
             state.event.type == :final do
          %State{state | reading: :prelim_dupes}
        else
          state
        end

      state.reading == :event ->
        parse_event(state, line)

      swim_error?(state, line) ->
        State.update_swim(state, fn [swim | rest] ->
          [%Swim{swim | dq_reason: String.trim(line)} | rest]
        end)

      not is_nil(state.strategy) ->
        case apply(state.strategy, :"parse_#{state.reading}", [state, line]) do
          %State{} = s ->
            s

          nil ->
            if is_nil(state.fragment) do
              %State{state | fragment: line}
            else
              nil
            end
        end
    end
  end

  def extract_columns(state, line) do
    state.columns
    |> Enum.map(fn range -> String.slice(line, range) end)
    |> fix_columns()
    |> Enum.with_index()
    |> Enum.reduce(state.buffer, fn {column, i}, acc ->
      j = state.page * length(state.columns) + i
      Map.update(acc, j, [column], &[column | &1])
    end)
  end

  def fix_columns([one, two, three]) do
    [one, two] = fix_columns([one, two])
    [two, three] = fix_columns([two, three])
    [one, two, three]
  end

  def fix_columns([one, two]) do
    if two == "" or String.slice(one, -2, 2) == "  " do
      [one, two]
    else
      fix_columns([one <> String.first(two), String.slice(two, 1..-1//1)])
    end
  end

  def parse_meet_name_and_date(%State{meet: nil} = state, line) do
    with parsed when is_map(parsed) <-
           Regex.named_captures(
             ~r{
               \A\s+
               (?<name>.+?)\s*
               -\s*
               (?<month>\d+)/(?<day>\d+)/(?<year>\d+)\s*
               (?:to\s+\d+/\d+/\d+\s*)?
               \z
             }x,
             line
           ) do
      %State{state | reading: :results, meet: Meet.new(parsed)}
    end
  end

  def parse_meet_name_and_date(%State{meet: %Meet{}} = state, line) do
    %Meet{start_date: date, name: name} = state.meet

    if String.match?(
         line,
         ~r<
           \A\s+
           #{Regex.escape(name)}\s+
           -\s+
           #{date.month}/#{date.day}/#{date.year}\s*
           (?:to\s+\d+/\d+/\d+\s*)?
           \z
         >x
       ) do
      %State{state | reading: :results}
    else
      state
    end
  end

  def parse_results(state, line) do
    if String.match?(line, ~r{\A\s+Results\b}) do
      %State{state | reading: :event}
    else
      state
    end
  end

  def parse_prelim_dupes(state, _line) do
    state
  end

  def parse_event(state, "(" <> line) do
    with parsed when is_map(parsed) <- Regex.named_captures(@event_re, line),
         event when is_struct(event, Event) <- Event.new(parsed),
         true <-
           Enum.all?(
             ~w[number gender distance unit stroke relay]a,
             fn key ->
               Map.fetch!(state.event, key) == Map.fetch!(event, key)
             end
           ) do
      %State{state | reading: event_headers(event)}
    else
      _non_match -> nil
    end
  end

  def parse_event(state, line) do
    with parsed when is_map(parsed) <- Regex.named_captures(@event_re, line) do
      event = Event.new(parsed)
      %State{state | reading: event_headers(event), event: event}
    end
  end

  defp finished?(line) do
    String.match?(line, ~r{\s+(?:Team|Meet)\s+(?:Rankings|Scores)\s+})
  end

  defp buffering?(state) do
    is_list(state.columns) and is_map(state.buffer)
  end

  defp page_start?(line) do
    String.match?(line, ~r{\bHY-TEK's\s+MEET\s+MANAGER\b})
  end

  defp junk_line?(line) do
    String.match?(line, ~r{\A[\s=]*\z}) or
      String.match?(line, ~r{\AFirefox\b}) or
      String.match?(line, ~r{\A\d+\s+of\s+\d+\b}) or
      String.match?(line, ~r{\b608:36:40.00\b}) or
      String.match?(line, ~r{\bbrought\s+to\s+you\s+by\b})
  end

  defp new_event?(state, line) do
    state.reading in ~w[individual_swim relay_swim]a and
      String.match?(line, @event_re)
  end

  defp event_type?(state, line) do
    state.reading in ~w[individual_swim relay_swim]a and
      String.match?(line, @event_type_re)
  end

  defp swim_error?(state, line) do
    line = String.trim(line)

    state.reading in ~w[relay_swim individual_swim]a and
      is_list(state.meet.events[state.event]) and
      hd(state.meet.events[state.event]).dq? and
      Enum.any?(
        [
          "Early take-off",
          "False start",
          "Shoulders",
          "Did not finish",
          "Delay of meet",
          "Not on back",
          "Arms underwater recovery",
          "Scissors kick",
          "No touch at turn",
          "No touch on turn",
          "One hand touch",
          "Alternating Kick",
          "Declared false start",
          "Stroke Infraction",
          "Head did not break the surface",
          "Shoulders past vertical",
          "Multiple strokes past vertical",
          "Incomplete stroke cycle",
          "Downward butterfly kick",
          "Non-simultaneous touch",
          "Changed order"
        ],
        &String.starts_with?(line, &1)
      )
  end

  defp merge_lines(top, bottom) do
    parts = Enum.map([top, bottom], &String.trim_trailing/1)
    count = parts |> Enum.map(&String.length/1) |> Enum.max()

    result =
      parts
      |> Enum.map(fn p ->
        p |> String.pad_trailing(count) |> String.graphemes()
      end)
      |> Enum.zip()
      |> Enum.reduce_while([], fn
        {" ", " "}, acc -> {:cont, [" " | acc]}
        {" ", c}, acc when c != " " -> {:cont, [c | acc]}
        {c, " "}, acc when c != " " -> {:cont, [c | acc]}
        _conflict, _acc -> {:halt, {:error, "Unrecognized line:  #{top}"}}
      end)

    case result do
      chars when is_list(chars) ->
        "#{chars |> Enum.reverse() |> Enum.join()}\n"

      error ->
        error
    end
  end

  defp event_headers(event) do
    if event.relay do
      :relay_headers
    else
      :individual_headers
    end
  end

  defp post_process(meet) do
    {:ok,
     %Meet{
       meet
       | events:
           Enum.into(meet.events, Map.new(), fn {event, results} ->
             {event, Enum.reverse(results)}
           end)
     }}
  end
end
