class NormalizeDomainHostnames < ActiveRecord::Migration[8.1]
  def up
    Domain.find_each do |domain|
      normalized = domain.hostname.to_s
        .strip
        .sub(/\Ahttps?:\/\//i, "")
        .sub(/:\d+\z/, "")
        .sub(/\/.*\z/, "")
        .downcase
        .presence

      next if normalized == domain.hostname

      # If the normalized hostname already exists for this service, remove the duplicate.
      if Domain.exists?(hostname: normalized, service_id: domain.service_id)
        domain.destroy!
      else
        domain.update_column(:hostname, normalized)
      end
    end
  end

  def down
    # irreversible
  end
end
