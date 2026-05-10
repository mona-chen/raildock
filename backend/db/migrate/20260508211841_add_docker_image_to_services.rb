class AddDockerImageToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :docker_image, :string
  end
end
