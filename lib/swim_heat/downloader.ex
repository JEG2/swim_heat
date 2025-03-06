defmodule SwimHeat.Downloader do
  alias SwimHeat.PrivFiles

  @base_url "https://ossaaillustrated.com/swimming/"
  @meets_header "2024-25 SWIM MEET RESULTS"
  @regionals_date "2025-02-08"
  @state_date "2025-02-24"
  @months ~w[January February March
             April May June
             July August September
             October November December]

  def download_all(options \\ []) do
    gather_urls()
    |> download_files(options)
  end

  defp gather_urls do
    listing =
      @base_url
      |> Req.get!()
      |> Map.fetch!(:body)
      |> String.split("\n")
      |> Enum.filter(fn line -> String.match?(line, ~r{\S}) end)

    season =
      listing
      |> Enum.drop_while(&(not String.contains?(&1, @meets_header)))
      |> Enum.drop(1)
      |> Enum.take_while(&String.contains?(&1, ".pdf"))
      |> Enum.map(fn line ->
        parsed = parse_download_link(line)
        [name, date] = String.split(parsed["name"], ~r{\s*&#8211;\s*}, parts: 2)

        [month, day, year] = String.split(date, ~r{,?\s+}, parts: 3)
        i = Enum.find_index(@months, &(&1 == month))
        day = String.replace(day, ~r{\D.+}, "")
        date = Date.new!(String.to_integer(year), i + 1, String.to_integer(day))

        name =
          if String.contains?(name, ",") do
            [schools, location] = String.split(name, ~r{\s+at\s+}, parts: 2)

            schools =
              schools
              |> String.split(~r{,\s*})
              |> Enum.map(fn s ->
                s
                |> String.split()
                |> Enum.map(&String.first/1)
              end)
              |> Enum.join(" ")

            PrivFiles.clean_name("#{schools} at #{location}")
          else
            PrivFiles.clean_name(name)
          end

        {parsed["url"], "#{Date.to_iso8601(date)}_#{name}.pdf"}
      end)

    regionals =
      listing
      |> Enum.filter(fn line ->
        String.match?(line, ~r{6A\s+(?:East|West)\s+Regional\s+Results})
      end)
      |> Enum.map(fn line ->
        parsed = parse_download_link(line)
        name = String.replace(parsed["name"], ~r{\A\d+}, "")
        {parsed["url"], "#{@regionals_date}_#{PrivFiles.clean_name(name)}.pdf"}
      end)

    state =
      listing
      |> Enum.filter(fn line ->
        String.match?(line, ~r{6A\s+State\s+Finals\s+Results})
      end)
      |> Enum.map(fn line ->
        parsed = parse_download_link(line)
        name = String.replace(parsed["name"], ~r{\A\d+}, "")
        {parsed["url"], "#{@state_date}_#{PrivFiles.clean_name(name)}.pdf"}
      end)

    season ++ regionals ++ state
  end

  defp parse_download_link(line) do
    Regex.named_captures(
      ~r{<a\s+href="(?<url>[^"]+)"[^>]*>(?<name>[^<]+)},
      line
    )
  end

  defp download_files(files, options) do
    force? = Keyword.get(options, :force, false)

    Enum.each(files, fn {url, file_name} ->
      path = PrivFiles.pdf(file_name)

      if force? or not File.exists?(path) do
        Process.sleep(1_000)
        data = Req.get!(url).body
        File.write!(path, data, [:binary])
      end
    end)
  end
end
