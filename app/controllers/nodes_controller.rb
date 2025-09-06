class NodesController < ApplicationController
  before_action :set_cluster
  before_action :set_providers, only: %i[ new create edit update ]
  before_action :set_node, only: %i[ show edit update destroy ]

  # GET /nodes or /nodes.json
  def index
    @nodes = @cluster.nodes.all
  end

  # GET /nodes/1 or /nodes/1.json
  def show
  end

  # GET /nodes/new
  def new
    @node = @cluster.nodes.new
  end

  # GET /nodes/1/edit
  def edit
  end

  # POST /nodes or /nodes.json
  def create
    @node = @cluster.nodes.new(node_params)

    respond_to do |format|
      if @node.save
        format.html { redirect_to [@cluster, @node], notice: "Node was successfully created." }
        format.json { render :show, status: :created, location: [@cluster, @node] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @node.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /nodes/1 or /nodes/1.json
  def update
    respond_to do |format|
      if @node.update(node_params)
        format.html { redirect_to [@cluster, @node], notice: "Node was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: [@cluster, @node] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @node.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /nodes/1 or /nodes/1.json
  def destroy
    @node.destroy!

    respond_to do |format|
      format.html { redirect_to cluster_nodes_path(@cluster), notice: "Node was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def config_partial
    @provider = Provider.find(params[:provider_id])
    @node = @cluster.nodes.find_by_id(params[:node_id])
    if @node == nil
      @node = @cluster.nodes.new(provider: @provider)
      @node.build_node_settings!
    end
    render "nodes/config_partial"
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_providers
      @providers = Provider.all
    end

    def set_cluster
      @cluster = Cluster.find(params.expect(:cluster_id))
    end

    def set_node
      @node = @cluster.nodes.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def node_params
      params.expect(node: [
        :provider_id,
        :name,
        node_settings_attributes: [
          [ :id, :provider_type_node_option_id, :key, :value ]
        ]
      ])
    end
end
