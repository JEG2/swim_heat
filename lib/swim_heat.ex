defmodule SwimHeat do
  alias SwimHeat.Database
  alias SwimHeat.Parser.State.Event
  alias SwimHeat.Parser.State.Meet
  alias SwimHeat.Parser.State.Swim
  alias SwimHeat.PrivFiles
  require Database

  def build_database do
    PrivFiles.create_directories()

    SwimHeat.Downloader.download_all()
    SwimHeat.PDFReader.convert_all()

    {parsed, []} =
      SwimHeat.Parser.stream_meets()
      |> Enum.split_with(fn result -> elem(result, 0) == :ok end)

    Enum.each(parsed, fn {:ok, meet} ->
      Database.create_db()
      m = Meet.to_record(meet)

      if is_nil(Database.get_record(:meet, Database.meet(m, :id))) do
        :ok = Database.store_record(m)

        Enum.each(meet.events, fn {event, swims} ->
          e = Event.to_record(event)
          :ok = Database.store_record(e)

          :ok =
            Database.store_join(
              meet: Database.meet(m, :id),
              event: Database.event(e, :id)
            )

          swims
          |> Enum.with_index()
          |> Enum.each(fn {swim, i} ->
            sr = Swim.to_swimmer_record(swim)
            :ok = Database.store_record(sr)

            sw =
              Swim.to_swim_record(
                [
                  Database.meet(m, :id),
                  Database.event(e, :id),
                  i
                ],
                swim
              )

            :ok = Database.store_record(sw)

            :ok =
              Database.store_join(
                meet: Database.meet(m, :id),
                event: Database.event(e, :id),
                swimmer: Database.swimmer(sr, :id),
                swim: Database.swim(sw, :id)
              )
          end)
        end)
      end
    end)
  end
end
