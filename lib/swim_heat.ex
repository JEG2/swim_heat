defmodule SwimHeat do
  alias SwimHeat.PrivFiles

  def build_database do
    PrivFiles.create_directories()

    SwimHeat.Downloader.download_all()
    SwimHeat.PDFReader.convert_all()

    {parsed, errors} =
      SwimHeat.Parser.stream_meets()
      |> Stream.drop(27)
      |> Enum.take(1)
      |> Enum.split_with(fn result -> elem(result, 0) == :ok end)

    # parsed |> Enum.at(2) |> IO.inspect()
    parsed_count = length(parsed)
    IO.puts("Parsed #{parsed_count} of #{parsed_count + length(errors)}.")
    List.first(errors)
  end
end
