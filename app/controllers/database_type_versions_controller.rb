class DatabaseTypeVersionsController < ApplicationController
  before_action :set_database_type
  before_action :set_database_type_version, only: [ :show, :edit, :update, :destroy, :test_installation, :set_default ]

  # GET /database_types/1/database_type_versions
  def index
    @database_type_versions = @database_type.database_type_versions.order(:version)
  end

  # GET /database_types/1/database_type_versions/1
  def show
  end

  # GET /database_types/1/database_type_versions/new
  def new
    @database_type_version = @database_type.database_type_versions.build

    # Set some sensible defaults based on database type
    case @database_type.slug
    when "postgresql"
      @database_type_version.default_port = 5432
      @database_type_version.service_name = "postgresql"
    when "mysql"
      @database_type_version.default_port = 3306
      @database_type_version.service_name = "mysql"
    when "mongodb"
      @database_type_version.default_port = 27017
      @database_type_version.service_name = "mongod"
    when "cassandra"
      @database_type_version.default_port = 9042
      @database_type_version.service_name = "cassandra"
    end
  end

  # GET /database_types/1/database_type_versions/1/edit
  def edit
  end

  # POST /database_types/1/database_type_versions
  def create
    @database_type_version = @database_type.database_type_versions.build(database_type_version_params)

    if @database_type_version.save
      redirect_to [ @database_type, @database_type_version ], notice: "Database type version was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /database_types/1/database_type_versions/1
  def update
    if @database_type_version.update(database_type_version_params)
      redirect_to [ @database_type, @database_type_version ], notice: "Database type version was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /database_types/1/database_type_versions/1
  def destroy
    if @database_type_version.nodes.exists?
      redirect_to [ @database_type, @database_type_version ], alert: "Cannot delete version that has nodes. Please delete all nodes first."
      return
    end

    @database_type_version.destroy
    redirect_to database_type_database_type_versions_path(@database_type), notice: "Database type version was successfully deleted."
  end

  # POST /database_types/1/database_type_versions/1/set_default
  def set_default
    # Remove default from all other versions
    @database_type.database_type_versions.update_all(is_default: false)

    # Set this version as default
    @database_type_version.update!(is_default: true)

    redirect_to [ @database_type, @database_type_version ], notice: "Version set as default successfully."
  end

  # GET /database_types/1/database_type_versions/1/test_installation
  def test_installation
    @test_results = {
      version: @database_type_version.version,
      install_command: @database_type_version.install_command,
      default_port: @database_type_version.default_port,
      service_name: @database_type_version.service_name
    }

    # Test if the installation command looks valid
    @test_results[:command_analysis] = analyze_install_command(@database_type_version.install_command)

    # Test if config template is valid (if present)
    if @database_type_version.config_template.present?
      @test_results[:template_analysis] = analyze_config_template(@database_type_version.config_template)
    end

    respond_to do |format|
      format.html
      format.json { render json: @test_results }
    end
  end

  # GET /database_types/1/database_type_versions/1/preview_config
  def preview_config
    @database_type_version = @database_type.database_type_versions.find(params[:id])

    # Sample variables for preview
    @sample_variables = {
      "cluster_name" => "sample_cluster",
      "listen_address" => "192.168.1.100",
      "default_port" => @database_type_version.default_port,
      "bind_ip" => "0.0.0.0",
      "replica_set_name" => "sample_rs",
      "seeds" => "192.168.1.100,192.168.1.101",
      "auto_bootstrap" => "true"
    }

    begin
      if @database_type_version.config_template.present?
        @rendered_config = @database_type_version.rendered_config_template(@sample_variables)
        @preview_success = true
      else
        @rendered_config = "No configuration template defined for this version."
        @preview_success = false
      end
    rescue => e
      @rendered_config = "Error rendering template: #{e.message}"
      @preview_success = false
    end

    respond_to do |format|
      format.html
      format.json {
        render json: {
          rendered_config: @rendered_config,
          success: @preview_success,
          sample_variables: @sample_variables
        }
      }
    end
  end

  private

  def set_database_type
    @database_type = DatabaseType.find(params[:database_type_id])
  end

  def set_database_type_version
    @database_type_version = @database_type.database_type_versions.find(params[:id])
  end

  def database_type_version_params
    params.require(:database_type_version).permit(
      :version, :install_command, :config_template, :default_port,
      :service_name, :data_directory_pattern, :config_file_pattern, :is_default
    )
  end

  def analyze_install_command(command)
    analysis = {
      has_apt_update: command.include?("apt-get update") || command.include?("apt update"),
      has_repository_setup: command.include?("wget") && command.include?("apt-key"),
      has_package_install: command.include?("apt-get install") || command.include?("apt install"),
      estimated_complexity: "simple"
    }

    if analysis[:has_repository_setup]
      analysis[:estimated_complexity] = "complex"
    elsif analysis[:has_apt_update]
      analysis[:estimated_complexity] = "medium"
    end

    analysis[:recommendations] = []
    analysis[:recommendations] << "Consider adding 'apt-get update' before installation" unless analysis[:has_apt_update]
    analysis[:recommendations] << "Command looks good!" if analysis[:has_apt_update] && analysis[:has_package_install]

    analysis
  end

  def analyze_config_template(template)
    analysis = {
      has_erb_syntax: template.include?("<%") && template.include?("%>"),
      line_count: template.lines.count,
      estimated_size: template.bytesize
    }

    # Check for common template variables
    common_vars = [ "cluster_name", "listen_address", "default_port", "bind_ip" ]
    analysis[:uses_common_variables] = common_vars.any? { |var| template.include?(var) }

    analysis[:recommendations] = []
    analysis[:recommendations] << "Template uses ERB syntax correctly" if analysis[:has_erb_syntax]
    analysis[:recommendations] << "Consider using common variables like cluster_name, listen_address" unless analysis[:uses_common_variables]
    analysis[:recommendations] << "Template is quite large, consider breaking it down" if analysis[:line_count] > 100

    analysis
  end
end
