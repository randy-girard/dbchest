# frozen_string_literal: true

require "rails_helper"

RSpec.describe VersionCompatibilityService do
  describe ".postgresql_compatible?" do
    context "with Ubuntu 20.04 (focal)" do
      let(:ubuntu_version) { "20.04" }

      it "returns true for PostgreSQL 12" do
        expect(described_class.postgresql_compatible?(12, ubuntu_version)).to be true
      end

      it "returns true for PostgreSQL 13" do
        expect(described_class.postgresql_compatible?(13, ubuntu_version)).to be true
      end

      it "returns true for PostgreSQL 14" do
        expect(described_class.postgresql_compatible?(14, ubuntu_version)).to be true
      end

      it "returns true for PostgreSQL 15" do
        expect(described_class.postgresql_compatible?(15, ubuntu_version)).to be true
      end

      it "returns false for PostgreSQL 16" do
        expect(described_class.postgresql_compatible?(16, ubuntu_version)).to be false
      end

      it "returns false for PostgreSQL 17" do
        expect(described_class.postgresql_compatible?(17, ubuntu_version)).to be false
      end
    end

    context "with Ubuntu 22.04 (jammy)" do
      let(:ubuntu_version) { "22.04" }

      it "returns true for PostgreSQL 12" do
        expect(described_class.postgresql_compatible?(12, ubuntu_version)).to be true
      end

      it "returns true for PostgreSQL 15" do
        expect(described_class.postgresql_compatible?(15, ubuntu_version)).to be true
      end

      it "returns true for PostgreSQL 16" do
        expect(described_class.postgresql_compatible?(16, ubuntu_version)).to be true
      end

      it "returns true for PostgreSQL 17" do
        expect(described_class.postgresql_compatible?(17, ubuntu_version)).to be true
      end
    end

    context "with Ubuntu 24.04 (noble)" do
      let(:ubuntu_version) { "24.04" }

      it "returns true for all supported PostgreSQL versions" do
        [ 12, 13, 14, 15, 16, 17 ].each do |version|
          expect(described_class.postgresql_compatible?(version, ubuntu_version)).to be true
        end
      end
    end

    context "with nil Ubuntu version" do
      it "returns true (skips check)" do
        expect(described_class.postgresql_compatible?(16, nil)).to be true
      end
    end
  end

  describe ".mysql_compatible?" do
    context "with Ubuntu 20.04" do
      let(:ubuntu_version) { "20.04" }

      it "returns true for MySQL 5.7" do
        expect(described_class.mysql_compatible?("5.7", ubuntu_version)).to be true
      end

      it "returns true for MySQL 8.0" do
        expect(described_class.mysql_compatible?("8.0", ubuntu_version)).to be true
      end
    end

    context "with Ubuntu 22.04" do
      let(:ubuntu_version) { "22.04" }

      it "returns true for MySQL 8.0" do
        expect(described_class.mysql_compatible?("8.0", ubuntu_version)).to be true
      end

      it "returns false for MySQL 5.7" do
        expect(described_class.mysql_compatible?("5.7", ubuntu_version)).to be false
      end
    end
  end

  describe ".compatibility_info" do
    context "for PostgreSQL" do
      it "returns compatible info for PostgreSQL 15 on Ubuntu 20.04" do
        info = described_class.compatibility_info("postgresql", 15, "20.04")

        expect(info[:compatible]).to be true
        expect(info[:notes]).to be_an(Array)
        expect(info[:repository]).to include("apt-archive.postgresql.org")
        expect(info[:ubuntu_codename]).to eq("focal")
      end

      it "returns incompatible info for PostgreSQL 16 on Ubuntu 20.04" do
        info = described_class.compatibility_info("postgresql", 16, "20.04")

        expect(info[:compatible]).to be false
        expect(info[:notes]).to include(match(/not compatible/))
        expect(info[:error_message]).to include("not available")
      end

      it "returns compatible info for PostgreSQL 16 on Ubuntu 22.04" do
        info = described_class.compatibility_info("postgresql", 16, "22.04")

        expect(info[:compatible]).to be true
        expect(info[:notes]).to include(match(/requires Ubuntu 22.04/))
        expect(info[:repository]).to include("apt.postgresql.org")
      end
    end

    context "for MySQL" do
      it "returns compatible info for MySQL 8.0 on Ubuntu 22.04" do
        info = described_class.compatibility_info("mysql", "8.0", "22.04")

        expect(info[:compatible]).to be true
        expect(info[:default_version]).to eq("8.0")
      end

      it "returns incompatible info for MySQL 5.7 on Ubuntu 22.04" do
        info = described_class.compatibility_info("mysql", "5.7", "22.04")

        expect(info[:compatible]).to be false
        expect(info[:error_message]).to include("not available")
      end
    end

    context "for unknown database type" do
      it "returns compatible by default" do
        info = described_class.compatibility_info("mongodb", "6.0", "22.04")

        expect(info[:compatible]).to be true
        expect(info[:notes]).to eq([])
      end
    end
  end

  describe ".postgresql_repository_url" do
    it "returns archive repository for PostgreSQL 12" do
      url = described_class.postgresql_repository_url(12, "20.04")
      expect(url).to eq("http://apt-archive.postgresql.org/pub/repos/apt/")
    end

    it "returns archive repository for PostgreSQL 15" do
      url = described_class.postgresql_repository_url(15, "22.04")
      expect(url).to eq("http://apt-archive.postgresql.org/pub/repos/apt/")
    end

    it "returns main repository for PostgreSQL 16" do
      url = described_class.postgresql_repository_url(16, "22.04")
      expect(url).to eq("http://apt.postgresql.org/pub/repos/apt/")
    end

    it "returns main repository for PostgreSQL 17" do
      url = described_class.postgresql_repository_url(17, "22.04")
      expect(url).to eq("http://apt.postgresql.org/pub/repos/apt/")
    end
  end

  describe ".recommended_postgresql_version" do
    it "returns 15 for Ubuntu 20.04" do
      expect(described_class.recommended_postgresql_version("20.04")).to eq(15)
    end

    it "returns 17 for Ubuntu 22.04" do
      expect(described_class.recommended_postgresql_version("22.04")).to eq(17)
    end

    it "returns 17 for Ubuntu 24.04" do
      expect(described_class.recommended_postgresql_version("24.04")).to eq(17)
    end

    it "returns 15 for unknown Ubuntu version" do
      expect(described_class.recommended_postgresql_version("18.04")).to eq(15)
    end
  end

  describe ".supported_postgresql_versions" do
    it "returns correct versions for Ubuntu 20.04" do
      versions = described_class.supported_postgresql_versions("20.04")
      expect(versions).to eq([ 12, 13, 14, 15 ])
    end

    it "returns correct versions for Ubuntu 22.04" do
      versions = described_class.supported_postgresql_versions("22.04")
      expect(versions).to eq([ 12, 13, 14, 15, 16, 17 ])
    end

    it "returns empty array for unknown Ubuntu version" do
      versions = described_class.supported_postgresql_versions("18.04")
      expect(versions).to eq([])
    end
  end

  describe ".validate_compatibility!" do
    it "does not raise error for compatible versions" do
      expect {
        described_class.validate_compatibility!("postgresql", 15, "20.04")
      }.not_to raise_error
    end

    it "raises error for incompatible versions" do
      expect {
        described_class.validate_compatibility!("postgresql", 16, "20.04")
      }.to raise_error(VersionCompatibilityService::VersionCompatibilityError, /not available/)
    end

    it "returns compatibility info when valid" do
      info = described_class.validate_compatibility!("postgresql", 15, "22.04")
      expect(info[:compatible]).to be true
    end
  end

  describe ".generate_postgresql_install_command" do
    it "generates correct command for PostgreSQL 15 on Ubuntu 20.04" do
      command = described_class.generate_postgresql_install_command(15, "20.04")

      expect(command).to include("postgresql-15")
      expect(command).to include("apt-archive.postgresql.org")
      expect(command).to include("apt-get install")
    end

    it "generates correct command for PostgreSQL 16 on Ubuntu 22.04" do
      command = described_class.generate_postgresql_install_command(16, "22.04")

      expect(command).to include("postgresql-16")
      expect(command).to include("apt.postgresql.org")
      expect(command).not_to include("apt-archive")
    end

    it "generates error command for PostgreSQL 16 on Ubuntu 20.04" do
      command = described_class.generate_postgresql_install_command(16, "20.04")

      expect(command).to include("ERROR")
      expect(command).to include("not compatible")
      expect(command).to include("exit 1")
    end

    it "generates command without version check when Ubuntu version not provided" do
      command = described_class.generate_postgresql_install_command(16)

      expect(command).to include("postgresql-16")
      expect(command).not_to include("ERROR")
    end
  end
end
