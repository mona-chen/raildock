# frozen_string_literal: true

# Compares two environments in the same project and reports what the target is
# missing, what it has drifted on, and what it holds that the source does not.
#
# The comparison is by *service name* — the only handle an operator has that is
# stable across environments — and the configuration comparison is delegated to
# `ServiceBlueprint`, so the diff and the duplicate flow agree on what counts as
# configuration by construction.
#
# This is read-only. `EnvironmentSync` is the only thing that writes, and it
# consumes exactly this plan, which is what makes the "review the staged
# changes" step in the UI trustworthy.
class EnvironmentDiff
  # `changes` names the differing fields, never their values: environment
  # variable values are secrets and these labels are rendered in the UI.
  Entry = Struct.new(:name, :service_id, :changes, keyword_init: true) do
    def as_json(*)
      { "name" => name, "service_id" => service_id, "changes" => changes }
    end
  end

  Plan = Struct.new(:source, :target, :added, :edited, :removed, keyword_init: true) do
    def changes?
      added.any? || edited.any? || removed.any?
    end

    def as_json(*)
      {
        "source_environment_id" => source.id,
        "source_environment_name" => source.name,
        "target_environment_id" => target.id,
        "target_environment_name" => target.name,
        "added" => added.map(&:as_json),
        "edited" => edited.map(&:as_json),
        "removed" => removed.map(&:as_json),
        "summary" => {
          "added" => added.size,
          "edited" => edited.size,
          "removed" => removed.size,
          "in_sync" => !changes?
        }
      }
    end
  end

  def initialize(source:, target:)
    @source = source
    @target = target
  end

  def call
    source_by_name = services_by_name(@source)
    target_by_name = services_by_name(@target)

    added = (source_by_name.keys - target_by_name.keys).sort.map do |name|
      Entry.new(name: name, service_id: source_by_name[name].id, changes: [ "new service" ])
    end

    edited = (source_by_name.keys & target_by_name.keys).sort.filter_map do |name|
      changes = ServiceBlueprint.new(source_by_name[name]).differences_from(ServiceBlueprint.new(target_by_name[name]))
      next if changes.empty?

      Entry.new(name: name, service_id: target_by_name[name].id, changes: changes)
    end

    removed = (target_by_name.keys - source_by_name.keys).sort.map do |name|
      Entry.new(name: name, service_id: target_by_name[name].id, changes: [ "not in #{@source.name}" ])
    end

    Plan.new(source: @source, target: @target, added: added, edited: edited, removed: removed)
  end

  private
    # Latest service wins if a name is duplicated, which `Service#name` does not
    # currently forbid but a manifest or an import can produce.
    def services_by_name(environment)
      environment.services.order(:id).each_with_object({}) { |service, memo| memo[service.name] = service }
    end
end
