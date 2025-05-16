defmodule SwimHeat.Database do
  alias SwimHeat.PrivFiles
  import Record, only: [defrecord: 2]

  defrecord(:meet, id: nil, start_date: nil, name: nil)

  defrecord(
    :event,
    id: nil,
    number: nil,
    gender: nil,
    distance: nil,
    unit: nil,
    stroke: nil,
    relay?: false,
    type: nil,
    records: %{}
  )

  defrecord(:swimmer, id: nil, name: nil, year: nil, school: nil)

  defrecord(
    :swim,
    id: nil,
    place: nil,
    seed: nil,
    time: nil,
    points: nil,
    dq?: false,
    dq_reason: nil,
    qualified?: false,
    splits: [],
    swimmers: []
  )

  def create_db, do: open(:read_write, fn _db -> :ok end)

  def store_record(record) do
    open(:read_write, fn db ->
      [type, id | fields] = Tuple.to_list(record)
      :dets.insert(db, List.to_tuple([{type, id} | fields]))
    end)
  end

  def get_record(type, id) do
    open(fn db ->
      case :dets.lookup(db, {type, id}) do
        [persisted] ->
          [{^type, ^id} | fields] = Tuple.to_list(persisted)
          List.to_tuple([type, id | fields])

        [] ->
          nil
      end
    end)
  end

  def store_join(types_and_ids) do
    open(:read_write, fn db ->
      :dets.insert(db, {types_and_ids})
    end)
  end

  def list_schools do
    open(fn db ->
      :dets.match(db, {{:swimmer, :_}, :_, :_, :"$1"})
      |> List.flatten()
      |> Enum.sort()
      |> Enum.uniq()
    end)
  end

  def list_swimmers(school) do
    open(fn db ->
      :dets.match(db, {{:swimmer, :_}, :"$1", :_, school})
      |> List.flatten()
      |> Enum.sort()
      |> Enum.uniq()
    end)
  end

  def list_swims(school, swimmer) do
    open(fn db ->
      [[id]] = :dets.match(db, {{:swimmer, :"$1"}, swimmer, :_, school})

      swims =
        db
        |> :dets.match({[meet: :"$1", event: :"$2", swimmer: id, swim: :"$3"]})
        |> Enum.map(fn [meet_id, event_id, swim_id] ->
          m = get_record(:meet, meet_id)
          e = get_record(:event, event_id)
          s = get_record(:swim, swim_id)

          %{
            meet: %{
              start_date: meet(m, :start_date),
              name: meet(m, :name)
            },
            event: %{
              number: event(e, :number),
              gender: event(e, :gender),
              distance: event(e, :distance),
              unit: event(e, :unit),
              stroke: event(e, :stroke),
              relay?: event(e, :relay?),
              type: event(e, :type),
              records: event(e, :records)
            },
            swim: %{
              place: swim(s, :place),
              seed: swim(s, :seed),
              time: swim(s, :time),
              points: swim(s, :points),
              dq?: swim(s, :dq?),
              dq_reason: swim(s, :dq_reason),
              qualified?: swim(s, :qualified?),
              splits: swim(s, :splits),
              swimmers: swim(s, :swimmers)
            }
          }
        end)
        |> Enum.sort_by(fn s ->
          [
            Date.to_iso8601(s.meet.start_date),
            s.event.number
          ]
        end)

      swimmer = get_record(:swimmer, id)

      {%{
         name: swimmer(swimmer, :name),
         school: swimmer(swimmer, :school)
       }, swims}
    end)
  end

  # defp open, do: open(:read, nil)

  defp open(fun) when is_function(fun), do: open(:read, fun)
  defp open(mode) when is_atom(mode), do: open(mode, nil)

  defp open(mode, nil) do
    path = String.to_charlist(PrivFiles.database_path())

    case :dets.open_file(:swim_db, access: mode, file: path) do
      {:ok, db} -> {:ok, db}
      error -> error
    end
  end

  defp open(mode, fun) do
    with {:ok, db} <- open(mode) do
      try do
        fun.(db)
      after
        close(db)
      end
    end
  end

  defp close(db), do: :dets.close(db)
end
