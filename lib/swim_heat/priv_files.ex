defmodule SwimHeat.PrivFiles do
  @conversion_script_path Path.join(~w[priv scripts pdf_to_txt.rb])
  @database_path Path.join(~w[priv database swim_db])
  @pdf_dir Path.join(~w[priv meet_results pdf])
  @txt_dir Path.join(~w[priv meet_results txt])

  def conversion_script_path, do: @conversion_script_path
  def database_path, do: @database_path

  def pdf(file_name) do
    Path.join(@pdf_dir, file_name)
  end

  def all_pdfs do
    @pdf_dir
    |> Path.join("*.pdf")
    |> Path.wildcard()
  end

  def txt(file_name) do
    Path.join(@txt_dir, file_name)
  end

  def all_txts do
    @txt_dir
    |> Path.join("*.txt")
    |> Path.wildcard()
  end

  def pdf_to_txt(path) do
    txt(Path.basename(path, ".pdf") <> ".txt")
  end

  def create_directories do
    File.mkdir_p!(Path.dirname(@database_path))
    File.mkdir_p!(@pdf_dir)
    File.mkdir_p!(@txt_dir)
  end

  def clean_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r{[^a-z0-9]+}, "_")
  end
end
