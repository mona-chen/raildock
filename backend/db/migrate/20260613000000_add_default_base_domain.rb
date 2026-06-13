class AddDefaultBaseDomain < ActiveRecord::Migration[8.1]
  def change
    change_column_default :servers, :base_domain, from: nil, to: "sslip.io"
  end
end
