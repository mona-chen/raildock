# frozen_string_literal: true

# Fast inline job that computes a manifest diff without applying changes.
# Used for real-time preview as the user edits their manifest.
class ManifestPreviewJob < ApplicationJob
  queue_as :default

  def perform(project_id, content = nil, format = nil)
    project = Project.find_by(id: project_id)
    return unless project

    content ||= project.manifest_content
    format ||= project.manifest_format || "raildock.toml"
    return unless content.present?

    desired = ManifestParser.parse(content, filename: format)
    reconciler = ManifestReconciler.new(project, desired)
    changes = reconciler.diff

    # Broadcast preview result via ActionCable
    ActionCable.server.broadcast(
      "project_#{project_id}",
      {
        type: "manifest_preview",
        changes: changes.map(&:to_h),
        severity: ChangeClassifier.aggregate(changes),
        by_severity: ChangeClassifier.group_by_severity(changes).transform_values(&:count),
        warnings: desired.warnings
      }
    )
  rescue ManifestParser::ParseError => e
    ActionCable.server.broadcast(
      "project_#{project_id}",
      { type: "manifest_preview_error", error: e.message }
    )
  end
end
