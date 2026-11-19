class AddApiTokenToActivityEvents < ActiveRecord::Migration[8.0]
  def change
    # Which token caused a write, when an agent caused it. Null for a human
    # action, and nullified (not deleted) when the token or organization is
    # removed so the event stays resolvable.
    add_reference :activity_events, :api_token, foreign_key: { on_delete: :nullify }, index: true
  end
end
