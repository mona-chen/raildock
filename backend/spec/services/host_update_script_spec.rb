require "rails_helper"
require "tmpdir"
require "fileutils"
require "open3"

RSpec.describe "Detached host update lifecycle" do
  def run_update(failure = "")
    Dir.mktmpdir("raildock-update-") do |dir|
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(dir, "docker-compose.yml"), "services: {}\n")
      File.write(File.join(dir, ".env"), "RAILDOCK_VERSION=0.1.0\n")
      commands = {
        "sleep" => "#!/bin/sh\nexit 0\n",
        "flock" => "#!/bin/sh\n[ \"$TEST_FAILURE\" != busy ]\n",
        "timeout" => "#!/bin/sh\nshift\nexec \"$@\"\n",
        "docker" => <<~SH
          #!/usr/bin/env ruby
          dir = ENV.fetch("TEST_UPDATE_DIR")
          args = ARGV
          File.open(File.join(dir, "commands"), "a") { |file| file.puts(args.join(" ")) }
          if args.include?("ps")
            puts "container"
          elsif args.first == "image"
            puts "RAILDOCK_VERSION=0.1.0"
          elsif args.first == "inspect" && args.join.include?(".Image")
            puts "sha256:" + "a" * 64
          elsif args.first == "inspect"
            puts(File.exist?(File.join(dir, "rollback")) || ENV["TEST_FAILURE"] != "health" ? "healthy" : "unhealthy")
          elsif args.first == "exec"
            exit 1 if ENV["TEST_FAILURE"] == "backup"
            puts "-- test database dump"
          elsif args.include?("up")
            File.write(File.join(dir, "rollback"), "yes") if args.any? { |arg| arg.end_with?("rollback.yml") }
          end
        SH
      }
      commands.each do |name, content|
        path = File.join(bin, name)
        File.write(path, content)
        File.chmod(0o755, path)
      end
      id = "a" * 32
      env = { "PATH" => "#{bin}:#{ENV.fetch('PATH')}", "TEST_UPDATE_DIR" => dir, "TEST_FAILURE" => failure }
      _, _, result = Open3.capture3(env, "bash", Rails.root.join("lib/raildock/host_update.sh").to_s, dir, "0.2.0", id)
      status = JSON.parse(File.read(File.join(dir, "data/updates", id, "status.json")))
      yield dir, result, status
    end
  end

  it "backs up the control database before replacement and verifies health" do
    run_update do |dir, result, status|
      expect(result).to be_success
      expect(status["status"]).to eq("completed")
      expect(File.read(File.join(dir, ".env"))).to include("RAILDOCK_VERSION=0.2.0")
      commands = File.read(File.join(dir, "commands"))
      expect(commands.index("pg_dump")).to be < commands.index("up -d")
    end
  end

  it "restores the previous immutable image when the replacement is unhealthy" do
    run_update("health") do |dir, result, status|
      expect(result).not_to be_success
      expect(status["status"]).to eq("rolled_back")
      expect(File.read(File.join(dir, ".env"))).to include("RAILDOCK_VERSION=0.1.0")
      expect(File.read(File.join(dir, "data/updates", "a" * 32, "rollback.yml"))).to include("sha256:#{'a' * 64}")
    end
  end

  it "leaves the app untouched if its database cannot be backed up" do
    run_update("backup") do |dir, result, status|
      expect(result).not_to be_success
      expect(status["status"]).to eq("failed")
      expect(File.read(File.join(dir, "commands"))).not_to include("up -d")
    end
  end

  it "refuses concurrent updates before contacting Docker" do
    run_update("busy") do |dir, result, status|
      expect(result).not_to be_success
      expect(status["status"]).to eq("busy")
      expect(File).not_to exist(File.join(dir, "commands"))
    end
  end
end
