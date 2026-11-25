require "shellwords"
require "tempfile"

# Read and write files inside a running application container.
#
# Every command is fixed here and paths are passed as positional arguments. The
# browser never interpolates a user path into a shell script, and it only uses
# the running container's filesystem: a deploy replaces that filesystem, so
# persistent data still belongs in a Storage mount.
class AppFileBrowser
  class Error < StandardError
    attr_reader :code, :status

    def initialize(message, code: nil, status: :unprocessable_entity)
      super(message)
      @code = code
      @status = status
    end
  end

  MAX_ENTRIES = 500
  MAX_PREVIEW_BYTES = 200_000
  MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024
  MAX_UPLOAD_BYTES = 10 * 1024 * 1024

  attr_reader :process_type

  LIST_SCRIPT = <<~'SH'.strip.gsub("__MAX_ENTRIES__", MAX_ENTRIES.to_s)
    target=${1:-$(pwd)}
    cd "$target" 2>/dev/null || exit 3
    printf '%s\0' "$(pwd)"
    count=0
    for p in * .*; do
      [ "$p" = "." ] && continue
      [ "$p" = ".." ] && continue
      [ -e "$p" ] || [ -L "$p" ] || continue
      if [ -d "$p" ]; then
        kind=d
        size=0
      elif [ -f "$p" ]; then
        kind=f
        size=$(wc -c < "$p" 2>/dev/null | tr -d ' ')
      else
        kind=o
        size=0
      fi
      printf '%s\t%s\t%s\0' "$kind" "$size" "$p"
      count=$((count + 1))
      [ "$count" -ge __MAX_ENTRIES__ ] && break
    done
    exit 0
  SH

  FILE_SIZE_SCRIPT = <<~'SH'.strip
    p="$1"
    [ -f "$p" ] || exit 4
    [ -r "$p" ] || exit 5
    wc -c < "$p" 2>/dev/null | tr -d ' '
  SH

  PREVIEW_SCRIPT = <<~'SH'.strip.gsub("__MAX_PREVIEW__", (MAX_PREVIEW_BYTES + 1).to_s)
    p="$1"
    [ -f "$p" ] || exit 4
    [ -r "$p" ] || exit 5
    size=$(wc -c < "$p" 2>/dev/null | tr -d ' ')
    printf '%s\t' "$size"
    head -c __MAX_PREVIEW__ "$p" 2>/dev/null
  SH

  EXISTS_SCRIPT = <<~'SH'.strip
    [ -e "$1" ] || [ -L "$1" ]
  SH

  def initialize(service, process_type: "web", host: nil)
    @service = service
    @host = host || HostEngine.new(service.project.server)
    @process_type = normalize_process_type(process_type)
  end

  def list(path = nil)
    target = normalize_path(path, allow_blank: true)
    with_container do |container|
      result = run_script(container, LIST_SCRIPT, target.to_s)
      chunks = result[:output].to_s.split("\0")
      resolved = chunks.shift.to_s
      unless result[:success] && resolved.present?
        raise failure("Could not read #{target.presence || 'the working directory'}. Check that it exists and is readable.")
      end

      entries = chunks.filter_map do |chunk|
        kind, size, name = chunk.split("\t", 3)
        next if name.blank?

        {
          type: { "d" => "directory", "f" => "file" }.fetch(kind, "other"),
          name: name,
          size: size.to_i
        }
      end

      {
        path: resolved,
        entries: entries,
        truncated: entries.length >= MAX_ENTRIES,
        process_type: @process_type,
        process_types: process_types
      }
    end
  end

  def preview(path)
    target = normalize_path(path)
    with_container do |container|
      result = run_script(container, PREVIEW_SCRIPT, target)
      raise failure("Could not read #{target}. Check that it is a readable file.") unless result[:success]

      size_text, body = result[:output].to_s.split("\t", 2)
      size = size_text.to_i
      body = body.to_s
      text = body.dup.force_encoding("UTF-8")
      binary = body.include?("\0") || !text.valid_encoding?
      too_large = size > MAX_PREVIEW_BYTES

      {
        path: target,
        name: File.basename(target),
        size: size,
        binary: binary,
        too_large: too_large,
        content: binary || too_large ? nil : text
      }
    end
  end

  def download(path)
    target = normalize_path(path)
    with_container do |container|
      size = file_size(container, target)
      raise failure("#{File.basename(target)} is larger than the 20 MiB download limit.", status: :payload_too_large) if size > MAX_DOWNLOAD_BYTES

      Tempfile.create([ "raildock-app-file", File.extname(target) ]) do |file|
        result = @host.run_to_file("docker exec #{escape(container)} sh -c #{escape('cat "$1"')} sh #{escape(target)}", file.path)
        raise failure("Could not download #{target}.") unless result[:success]

        actual = File.size(file.path)
        raise failure("#{File.basename(target)} is larger than the 20 MiB download limit.", status: :payload_too_large) if actual > MAX_DOWNLOAD_BYTES

        return { data: File.binread(file.path), filename: safe_filename(File.basename(target)), size: actual }
      end
    end
  end

  def write(directory, filename, local_path, overwrite: false)
    dir = normalize_path(directory)
    name = safe_filename(filename)
    target = dir == "/" ? "/#{name}" : "#{dir}/#{name}"
    size = File.size(local_path)
    raise failure("#{name} is larger than the 10 MiB upload limit.", status: :payload_too_large) if size > MAX_UPLOAD_BYTES

    with_container do |container|
      if !overwrite && exists?(container, target)
        raise Error.new("#{name} already exists in #{dir}. Enable overwrite to replace it.", code: "file_exists", status: :conflict)
      end

      result = @host.run_with_file(
        "docker exec -i #{escape(container)} sh -c #{escape('cat > "$1"')} sh #{escape(target)}",
        local_path
      )
      raise failure("Could not write #{target}.") unless result[:success]

      { path: target, name: name, size: size }
    end
  end

  def process_types
    rows = @service.process_types.pluck(:name, :quantity)
    names = rows.select { |_, quantity| quantity.to_i.positive? }.map(&:first).reject(&:blank?)
    names.unshift("web").uniq
  end

  private

  def normalize_process_type(value)
    requested = value.to_s.strip.presence || "web"
    return requested if process_types.include?(requested)

    raise Error.new("This app has no #{requested} process. Choose one of: #{process_types.join(', ')}.", code: "unknown_process")
  end

  def with_container
    server = @service.project&.server
    raise failure("No server is configured for this project.") if server&.ssh_key.blank?

    @host.with_session do
      container = @host.dokku_container_name(@service.dokku_app_name, process_type: @process_type)
      if container.blank?
        raise Error.new("No running #{@process_type} container. Start or deploy the service first.", code: "container_unavailable")
      end
      yield container
    end
  end

  def run_script(container, script, argument)
    @host.run("docker exec #{escape(container)} sh -c #{escape(script)} sh #{escape(argument)}")
  end

  def file_size(container, target)
    result = run_script(container, FILE_SIZE_SCRIPT, target)
    raise failure("Could not read #{target}. Check that it is a readable file.") unless result[:success]

    Integer(result[:output].to_s.strip, exception: false) || raise(failure("Could not determine the size of #{target}."))
  end

  def exists?(container, target)
    run_script(container, EXISTS_SCRIPT, target)[:success]
  end

  def normalize_path(value, allow_blank: false)
    raw = value.to_s.strip
    return nil if raw.blank? && allow_blank
    raise Error.new("Path is required", code: "path_required") if raw.blank?
    raise Error.new("Invalid path", code: "invalid_path") if raw.include?("\0")

    segments = raw.tr("\\", "/").split("/").reject { |segment| segment.empty? || segment == "." || segment == ".." }
    "/#{segments.join('/')}"
  end

  def safe_filename(value)
    name = File.basename(value.to_s)
    if name.blank? || %w[. ..].include?(name) || name.match?(/[\x00-\x1f\x7f]/)
      raise Error.new("Invalid file name", code: "invalid_filename")
    end

    name
  rescue ArgumentError
    raise Error.new("Invalid file name", code: "invalid_filename")
  end

  def failure(message, status: :unprocessable_entity)
    Error.new(message, code: "file_unavailable", status: status)
  end

  def escape(value)
    Shellwords.escape(value.to_s)
  end
end
