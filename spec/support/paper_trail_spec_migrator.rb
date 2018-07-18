# frozen_string_literal: true

# Manage migrations including running generators to build them, and cleaning up strays
class PaperTrailSpecMigrator
  def initialize(migrations_path = Rails.root.join("db/migrate/"))
    migrations_path = Pathname.new(migrations_path) if migrations_path.is_a?(String)
    @migrations_path = migrations_path
  end

  def delete(filespec)
    Dir.glob(@migrations_path.join(filespec)).each do |file|
      File.delete(file)
    end
  end

  # Looks like the API for programatically running migrations will change
  # in rails 5.2. This is an undocumented change, AFAICT. Then again,
  # how many people use the programmatic interface? Most people probably
  # just use rake. Maybe we're doing it wrong.
  def migrate
    if ::ActiveRecord.gem_version >= ::Gem::Version.new("5.2.0.rc1")
      ::ActiveRecord::MigrationContext.new(@migrations_path).migrate
    else
      ::ActiveRecord::Migrator.migrate(@migrations_path)
    end
  end

  def generate_and_migrate(generator, arguments = [], dummy_version = nil)
    if dummy_version
      # Create a dummy migration file with a specific schema_migration version.
      # (Helpful to avoid trouble from the file system caching previous migrations
      # that were created with the exact same name since they get built at the exact
      # same second in time.)
      File.open(@migrations_path.join("#{dummy_version}_dummy_migration.rb"), "w+") do |f|
        f.write("class DummyMigration < ActiveRecord::Migration; end")
      end
    end
    files = Rails::Generators.invoke(generator, arguments, destination_root: Rails.root)
    last_version = files.last&.split("_")&.first&.split("/")&.last || "0"
    # This is the same as running:  rails db:migrate; rm db/migrate/######_migration_name.rb
    begin
      migrate
    ensure
      files.each do |file|
        File.delete(Rails.root.join(file))
      end
    end
    if dummy_version
      File.delete(@migrations_path.join("#{dummy_version}_dummy_migration.rb"))
    end
    # Wait up to 3 seconds for all migrations to complete
    attempt = 0
    until ActiveRecord::SchemaMigration.exists?(version: last_version)
      sleep 0.1
      break if (attempt += 1) == 30
    end
    # Return the maximum version number used while doing these migrations
    last_version
  end
end
