#!/usr/bin/env ruby
# Fix templates: replace CHANGE_ME with ${{ secret() }}
# Only does the simple replacement - depends_on handling needs more careful TOML parsing

script_path = File.expand_path(__FILE__, Dir.pwd)
TEMPLATES_DIR = File.expand_path("../backend/config/templates", File.dirname(script_path))

def process_template(content)
  result = content.dup

  # Replace CHANGE_ME with ${{ secret() }} in key = "CHANGE_ME" patterns
  result.gsub!(/^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"CHANGE_ME"$/m) do
    indent = $1
    key = $2
    "#{indent}#{key} = \"${{ secret() }}\""
  end

  # Replace CHANGE_ME in connection strings like postgres://...:CHANGE_ME@host/
  result.gsub!(/(postgres|redis|mysql|mariadb|mongodb):\/\/[^\:]+\:CHANGE_ME@/i) do
    "#{$1}:${{ secret() }}@"
  end

  result
end

fixed = 0
Dir.glob(File.join(TEMPLATES_DIR, "*.toml")).sort.each do |path|
  original = File.read(path)
  next unless original.include?("CHANGE_ME")

  updated = process_template(original)
  if updated != original
    changed = original.split("\n").zip(updated.split("\n")).count { |o, n| o != n }
    puts "M #{File.basename(path)} (#{changed} lines)"
    File.write(path, updated)
    fixed += 1
  end
end

puts "\nFixed #{fixed} templates"