require "pdf-reader"

reader = PDF::Reader.new(ARGV.shift)

reader.pages.each do |page|
  puts page.text
end
