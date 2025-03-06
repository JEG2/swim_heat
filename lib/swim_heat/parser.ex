defmodule SwimHeat.Parser do
  alias SwimHeat.Parser.State
  alias SwimHeat.Parser.State.Event
  alias SwimHeat.Parser.State.Meet
  alias SwimHeat.Parser.Strategy.OneEventAtATime
  alias SwimHeat.Parser.Strategy.MultipleEventsInColumns
  alias SwimHeat.PrivFiles

  @event_re ~r{
    \A\s*
    \(?
    (?:(?:Event\s+|\#)(?<number>\d+)\s+)?
    (?<gender>Girls|Boys|Women|Men)\s+
    (?<distance>\d+)\s+
    (?:SC\s+)?(?<unit>Yard|Meter)\s+
    (?<stroke>
      Free(?:style)?|
      (?:Back|Breast)(?:stroke)?|
      Butterfly|
      Fly|
      IM|
      Medley
    )\s*
    (?<relay>Relay)?
    \)?\s*
  }x

  def stream_meets do
    Stream.map(PrivFiles.all_txts(), fn file ->
      parse_meet(file)
    end)
  end

  def parse_meet(file) do
    file
    |> File.stream!()
    |> Stream.map(fn line -> String.replace(line, "Butter ly", "Butterfly") end)
    |> process_stream(file)
  end

  defp process_stream(enum, file, state \\ %State{}) do
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
          error -> {:halt, {:error, error, file, line}}
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
            %State{state | columns: nil, buffer: nil, reading: :event}
          )
        else
          post_process(state.meet)
        end

      error ->
        error
    end
  end

  def parse_line(state, line) do
    cond do
      is_binary(state.fragment) ->
        with merged when is_binary(merged) <-
               merge_lines(state.fragment, line) do
          parse_line(%State{state | fragment: nil}, merged)
        end

      finished?(line) ->
        %State{state | reading: :done}

      page_start?(line) ->
        %State{state | page: state.page + 1, reading: :meet_name_and_date}

      junk_line?(line) ->
        state

      state.reading in ~w[meet_name_and_date strategy]a ->
        apply(__MODULE__, :"parse_#{state.reading}", [state, line])

      is_list(state.columns) and is_map(state.buffer) ->
        buffer =
          state.columns
          |> Enum.with_index()
          |> Enum.reduce(state.buffer, fn {range, i}, acc ->
            column = String.slice(line, range)
            j = state.page * length(state.columns) + i
            Map.update(acc, j, [column], &[column | &1])
          end)

        %State{state | buffer: buffer}

      new_event?(state, line) ->
        parse_event(%State{state | reading: :event}, line)

      state.reading == :event ->
        parse_event(state, line)

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

  def parse_meet_name_and_date(%State{meet: nil} = state, line) do
    with parsed when is_map(parsed) <-
           Regex.named_captures(
             ~r{
               \A\s+
               (?<name>[^-]+?)\s+
               -\s+
               (?<month>\d+)/(?<day>\d+)/(?<year>\d+)\s*
               \z
             }x,
             line
           ) do
      %State{state | reading: :strategy, meet: Meet.new(parsed)}
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
           \z
         >x
       ) do
      %State{state | reading: :event}
    else
      {:error, "non-matching date"}
    end
  end

  def parse_strategy(%State{strategy: nil} = state, line) do
    cond do
      String.starts_with?(line, "#") ->
        parse_event(
          %State{
            state
            | reading: :event,
              strategy: MultipleEventsInColumns
          },
          line
        )

      true ->
        parse_event(
          %State{
            state
            | reading: :event,
              strategy: OneEventAtATime
          },
          line
        )
    end
  end

  def parse_event(%State{columns: nil} = state, "#" <> _rest = line) do
    columns =
      ~r{#[^#]+}
      |> Regex.scan(line)
      |> List.flatten()
      |> Enum.map_reduce(0, fn column, acc ->
        l = acc + String.length(column)
        {acc..(l - 1)//1, l}
      end)
      |> then(fn {ranges, _acc} ->
        List.replace_at(ranges, -1, Enum.at(ranges, -1).first..-1//1)
      end)

    parse_line(%State{state | columns: columns}, line)
  end

  def parse_event(state, "(" <> line) do
    with parsed when is_map(parsed) <- Regex.named_captures(@event_re, line),
         event when is_struct(event, Event) <- Event.new(parsed),
         true <-
           Enum.all?(~w[number gender distance unit stroke relay]a, fn key ->
             Map.fetch!(state.event, key) == Map.fetch!(event, key)
           end) do
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

  defp page_start?(line) do
    String.match?(line, ~r{\bHY-TEK's\s+MEET\s+MANAGER\b})
  end

  defp junk_line?(line) do
    String.match?(line, ~r{\A[\s=]*\z}) or
      String.match?(line, ~r{\AFirefox\b}) or
      String.match?(line, ~r{\A\d+\s+of\s+\d+\b}) or
      String.match?(line, ~r{\A\s+Results\b}) or
      String.match?(line, ~r{\A\s+Early\s+take-off\b}) or
      String.match?(line, ~r{\A\s+False\s+start\b}) or
      String.match?(line, ~r{\A\s+Shoulders\b}) or
      String.match?(line, ~r{\A\s+Did\s+not\s+finish\b}) or
      String.match?(line, ~r{\A\s+Delay\s+of\s+meet\b}) or
      String.match?(line, ~r{\A\s+Not\s+on\s+back\b})
  end

  defp new_event?(state, line) do
    state.reading in ~w[individual_swim relay_swim]a and
      String.match?(line, @event_re)
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
      chars when is_list(chars) -> chars |> Enum.reverse() |> Enum.join()
      error -> error
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
