# frozen_string_literal: true

# Records the Procfile process types a deployed app actually declares, and how
# many instances of each Dokku is running.
#
# Dokku only ever starts `web` on its own. Every other process type — a Sidekiq
# worker, a clock process — is created at zero and stays there until it is
# scaled explicitly, and nothing in the deploy output tells RailDock the type
# exists. Without this, `service.process_types` stays empty for Procfile-driven
# apps: the Scale UI has nothing to act on and background workers silently never
# run even though the Procfile asks for them.
class ProcessTypeDiscovery
  # Dokku lists these in `ps:scale` output, but they are one-shot commands run
  # by the deploy, not long-running processes. Scaling them to a non-zero
  # quantity would run e.g. `db:migrate` in a restart loop.
  NON_SCALABLE = %w[release postdeploy].freeze

  SCALE_ROW = /\A(?<name>[A-Za-z0-9][A-Za-z0-9_.-]*):\s*(?<quantity>\d+)\z/

  def initialize(engine)
    @engine = engine
  end

  # Returns { success:, discovered: [{ name:, quantity:, running:, created: }], error: }
  def sync(service)
    result = @engine.ps_scale_report(service.dokku_app_name)
    unless result[:success]
      return { success: false, discovered: [], error: result[:output].to_s.strip.truncate(200) }
    end

    scales = parse(result[:output])
    return { success: false, discovered: [], error: "No process types reported by ps:scale" } if scales.nil?

    { success: true, discovered: scales.map { |name, quantity| upsert(service, name, quantity) }, error: nil }
  end

  # Parses Dokku's `ps:scale <app>` table into { "web" => 1, "worker" => 0 }.
  def parse(output)
    scales = {}

    output.to_s.each_line do |line|
      match = SCALE_ROW.match(line.strip)
      next unless match

      name = match[:name].downcase
      next if NON_SCALABLE.include?(name)

      scales[name] = match[:quantity].to_i
    end

    scales.presence
  end

  private

  # A quantity is seeded from Dokku only the first time a type is recorded.
  # Later syncs must not overwrite a quantity the user chose, otherwise every
  # deploy would undo a deliberate scale-down.
  def upsert(service, name, quantity)
    process = service.process_types.find_or_initialize_by(name: name)
    created = process.new_record?
    process.quantity = quantity if created
    process.running = quantity
    process.command = "" if process.command.blank?
    process.save!

    { name: name, quantity: process.quantity, running: quantity, created: created }
  end
end
