# frozen_string_literal: true

# Classifies manifest field changes by severity.
# Determines whether a change can be hot-applied, requires a restart, or needs a full redeploy.
class ChangeClassifier
  SEVERITY = {
    reload: 0,
    restart: 1,
    redeploy: 2
  }.freeze

  FIELD_SEVERITY = {
    # Reload-only: can be applied without touching running processes
    env: :reload,
    domains: :reload,
    storage: :reload,
    proxy: :reload,
    traefik_labels: :reload,
    letsencrypt: :reload,
    maintenance_mode: :reload,

    # Restart: process needs restart but no rebuild
    limits: :restart,
    reservations: :restart,
    checks: :restart,
    cron: :restart,
    scaling: :restart,
    restart_policy: :restart,
    restart_max_retries: :restart,
    auto_deploy: :restart,
    depends_on: :restart,

    # Redeploy: full rebuild + deploy required
    builder: :redeploy,
    docker_image: :redeploy,
    git_repo: :redeploy,
    branch: :redeploy,
    source: :redeploy,
    root_directory: :redeploy,
    start_command: :redeploy,
    exposed: :redeploy,
    port: :redeploy,
    docker_options: :redeploy,
    version: :redeploy,
    subtype: :redeploy,
    category: :redeploy
  }.freeze

  # Classify a single field change
  def self.classify(field)
    FIELD_SEVERITY.fetch(field.to_sym, :redeploy)
  end

  # Given a list of changes, return the aggregate severity
  def self.aggregate(changes)
    return :reload if changes.empty?
    max_sev = changes.map { |c| SEVERITY.fetch(classify(change_field(c)), 0) }.max
    SEVERITY.key(max_sev)
  end

  # Group changes by severity
  def self.group_by_severity(changes)
    changes.group_by { |c| classify(change_field(c)) }
  end

  # Return human-readable description of severity
  def self.description(severity)
    case severity
    when :reload then "Configuration updated (no restart)"
    when :restart then "Services will be restarted"
    when :redeploy then "Full redeploy required"
    else "Unknown"
    end
  end

  def self.change_field(change)
    change.respond_to?(:field) ? change.field : change.fetch(:field)
  end
end
