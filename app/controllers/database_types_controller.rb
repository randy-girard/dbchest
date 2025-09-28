class DatabaseTypesController < ApplicationController
  before_action :set_database_type, only: [:show, :edit, :update, :destroy]

  # GET /database_types
  def index
    @database_types = DatabaseType.includes(:database_type_versions).order(:name)
    @pagy, @database_types = pagy(@database_types, items: 20) if defined?(Pagy)
  end

  # GET /database_types/1
  def show
    @database_type_versions = @database_type.database_type_versions.order(:version)
  end

  # GET /database_types/new
  def new
    @database_type = DatabaseType.new
  end

  # GET /database_types/1/edit
  def edit
  end

  # POST /database_types
  def create
    @database_type = DatabaseType.new(database_type_params)

    if @database_type.save
      redirect_to @database_type, notice: 'Database type was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /database_types/1
  def update
    if @database_type.update(database_type_params)
      redirect_to @database_type, notice: 'Database type was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /database_types/1
  def destroy
    if @database_type.clusters.exists?
      redirect_to database_types_path, alert: 'Cannot delete database type that has clusters. Please delete all clusters first.'
      return
    end

    @database_type.destroy
    redirect_to database_types_path, notice: 'Database type was successfully deleted.'
  end

  # GET /database_types/1/test_handler
  def test_handler
    @database_type = DatabaseType.find(params[:id])
    
    begin
      # Try to get the database type handler
      handler_class = DatabaseTypes::BaseDatabaseType.registry[@database_type.slug]
      
      if handler_class
        # Create a test version to test the handler
        test_version = @database_type.database_type_versions.first || @database_type.database_type_versions.build(
          version: "test",
          install_command: "echo 'test'",
          default_port: 5432,
          service_name: "test"
        )
        
        # Create a test node for the handler
        test_cluster = Cluster.new(name: "test", database_type: @database_type)
        test_node = Node.new(cluster: test_cluster, database_type_version: test_version)
        
        handler = handler_class.new(test_version, test_node)
        
        @test_results = {
          handler_found: true,
          handler_class: handler_class.name,
          supports_logical_replication: handler.supports_logical_replication?,
          supports_streaming_replication: handler.supports_streaming_replication?,
          primary_playbook: handler.respond_to?(:primary_playbook) ? handler.primary_playbook : "Not defined",
          replica_playbook: handler.respond_to?(:replica_playbook) ? handler.replica_playbook : "Not defined"
        }
      else
        @test_results = {
          handler_found: false,
          error: "No handler found for database type '#{@database_type.slug}'"
        }
      end
    rescue => e
      @test_results = {
        handler_found: false,
        error: "Error testing handler: #{e.message}"
      }
    end

    respond_to do |format|
      format.html
      format.json { render json: @test_results }
    end
  end

  private

  def set_database_type
    @database_type = DatabaseType.find(params[:id])
  end

  def database_type_params
    params.require(:database_type).permit(:name, :slug)
  end
end
