defmodule SwimHeat.PDFReader do
  alias SwimHeat.PrivFiles

  def convert_all(options \\ []) do
    force? = Keyword.get(options, :force, false)

    Enum.each(PrivFiles.all_pdfs(), fn from ->
      to = PrivFiles.pdf_to_txt(from)

      if force? or not File.exists?(to) do
        convert_one(from, to)
      end
    end)
  end

  def convert_one(from, to) do
    {text, 0} = System.cmd("ruby", [PrivFiles.conversion_script_path(), from])
    File.write!(to, text)
  end
end
