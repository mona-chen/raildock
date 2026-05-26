class AddCanvasPositionToServices < ActiveRecord::Migration[8.0]
  def change
    add_column :services, :canvas_x, :integer, default: nil
    add_column :services, :canvas_y, :integer, default: nil
  end
end
