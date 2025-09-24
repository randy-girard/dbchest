class ClustersController < ApplicationController
  before_action :set_cluster, only: %i[ show edit update destroy ]

  # GET /clusters or /clusters.json
  def index
    @clusters = Cluster.all
  end

  # GET /clusters/1 or /clusters/1.json
  def show
  end

  # GET /clusters/new
  def new
    @cluster = Cluster.new
    @database_types = DatabaseType.joins(:database_type_versions).distinct.order(:name)
  end

  # GET /clusters/1/edit
  def edit
    @database_types = DatabaseType.joins(:database_type_versions).distinct.order(:name)
  end

  # POST /clusters or /clusters.json
  def create
    @cluster = Cluster.new(cluster_params)

    respond_to do |format|
      if @cluster.save
        format.html { redirect_to @cluster, notice: "Cluster was successfully created." }
        format.json { render :show, status: :created, location: @cluster }
      else
        @database_types = DatabaseType.joins(:database_type_versions).distinct.order(:name)
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @cluster.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /clusters/1 or /clusters/1.json
  def update
    respond_to do |format|
      if @cluster.update(cluster_params)
        format.html { redirect_to @cluster, notice: "Cluster was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @cluster }
      else
        @database_types = DatabaseType.joins(:database_type_versions).distinct.order(:name)
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @cluster.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /clusters/1 or /clusters/1.json
  def destroy
    @cluster.destroy!

    respond_to do |format|
      format.html { redirect_to clusters_path, notice: "Cluster was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_cluster
      @cluster = Cluster.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def cluster_params
      params.expect(cluster: [ :name, :database_type_id ])
    end
end
