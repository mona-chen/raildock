class CheckAppUpdateJob < ApplicationJob
  queue_as :default

  def perform
    AppUpdateService.check_for_updates

    if AppUpdateService.auto_update_enabled? && AppUpdateService.last_check_result[:update_available]
      AppUpdateService.apply_update
    end
  end
end
