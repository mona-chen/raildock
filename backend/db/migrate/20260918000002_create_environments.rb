# frozen_string_literal: true

# Environments give a project named, switchable groupings of its services.
# Every project starts with a single default environment (`production`) and can
# add more (staging, qa, a per-teammate sandbox) without disturbing the others.
#
# This matches how Railway, Coolify and Dokploy all model it: the project is the
# container, the environment is the unit you switch between, and a production
# environment always exists and cannot be deleted.
#
# The project keeps its legacy `environment` column as a display label for the
# *primary* environment so the projects list and existing clients keep working.
class CreateEnvironments < ActiveRecord::Migration[8.1]
  def up
    create_table :environments do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :description
      t.boolean :is_default, null: false, default: false
      t.timestamps
    end
    add_index :environments, [ :project_id, :slug ], unique: true
    # At most one default environment per project, enforced by the database.
    add_index :environments, :project_id, unique: true, where: "is_default",
      name: "index_environments_on_one_default_per_project"

    # `on_delete: :nullify` keeps a project teardown from tripping over the
    # environment rows: the services are removed first, then the environments.
    add_column :services, :environment_id, :bigint
    add_index :services, :environment_id
    add_foreign_key :services, :environments, column: :environment_id, on_delete: :nullify

    backfill_default_environments!
  end

  def down
    remove_foreign_key :services, column: :environment_id
    remove_index :services, :environment_id
    remove_column :services, :environment_id
    drop_table :environments
  end

  private
    # Every existing project gets a default environment named after its current
    # `environment` label (or `production`), and every service in that project is
    # attached to it. A project with no services still gets the environment, so
    # switching to it in the UI is never empty for the wrong reason.
    def backfill_default_environments!
      connection.select_all("SELECT id, environment FROM projects").each do |row|
        project_id = row["id"]
        name = row["environment"].presence || "production"
        slug = name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "").presence || "production"

        environment_id = connection.select_value(<<~SQL.squish)
          INSERT INTO environments (project_id, name, slug, is_default, created_at, updated_at)
          VALUES (#{connection.quote(project_id)}, #{connection.quote(name)}, #{connection.quote(slug)}, TRUE, NOW(), NOW())
          RETURNING id
        SQL

        connection.execute(<<~SQL.squish)
          UPDATE services SET environment_id = #{connection.quote(environment_id)}
          WHERE project_id = #{connection.quote(project_id)}
        SQL
      end
    end
end
