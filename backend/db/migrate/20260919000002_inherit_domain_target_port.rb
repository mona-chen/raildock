# frozen_string_literal: true

# A domain's target_port used to be a snapshot of the app's port taken when the
# domain was added, and it defaulted to 80 in the database. Both went stale the
# moment the app's listening port changed or was detected, which is why
# auto-generated domains kept routing to 5000 while the app listened on 3001.
#
# A blank target_port now means "follow the app" (see Domain#resolved_target_port),
# so the column default goes away and the auto-generated domains — which were
# never an explicit user choice — are reset to inherit.
class InheritDomainTargetPort < ActiveRecord::Migration[8.1]
  def up
    change_column_default :domains, :target_port, from: 80, to: nil
    execute("UPDATE domains SET target_port = NULL WHERE temporary = TRUE")
  end

  def down
    change_column_default :domains, :target_port, from: nil, to: 80
  end
end
