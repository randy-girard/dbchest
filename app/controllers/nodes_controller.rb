class NodesController < ApplicationController
  before_action :set_cluster
  before_action :set_providers, only: %i[ new create edit update add_replica create_replica ]
  before_action :set_node, only: %i[ show edit update destroy add_replica create_replica ]

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
        @node.provision!
        format.html { redirect_to [ @cluster, @node ], notice: "Node was successfully created." }
        format.json { render :show, status: :created, location: [ @cluster, @node ] }
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
        format.html { redirect_to [ @cluster, @node ], notice: "Node was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: [ @cluster, @node ] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @node.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /nodes/1 or /nodes/1.json
  def destroy
    @node.deprovision!

    respond_to do |format|
      format.html { redirect_to cluster_path(@cluster), notice: "Node is being removed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def add_replica
    unless @node.primary?
      redirect_to [@cluster, @node], alert: "Cannot create replica of a replica node. Only primary nodes can have replicas." and return
    end

    @replica = @cluster.nodes.new(
      parent_node: @node,
      provider: @node.provider,
      name: "#{@node.name}-replica-#{@node.replicas.count + 1}"
    )
    @providers = Provider.all
    
    # Build initial settings for the default provider (parent's provider)
    @replica.build_node_settings!
    
    # Pre-populate with parent values, except for network settings
    network_settings = %w[ip_address gateway network subnet cidr]
    @node.node_settings.includes(:provider_type_node_option).each do |parent_setting|
      replica_setting = @replica.node_settings.find { |rs| rs.key == parent_setting.key }
      if replica_setting && !network_settings.include?(parent_setting.key)
        replica_setting.value = parent_setting.value
      end
    end
  end

  def create_replica
    unless @node.primary?
      redirect_to [@cluster, @node], alert: "Cannot create replica of a replica node. Only primary nodes can have replicas." and return
    end

    @replica = @cluster.nodes.new(replica_params)
    @replica.parent_node = @node

    respond_to do |format|
      if @replica.save
        # All settings now come from the form - no need to copy from parent

        @replica.provision_replica!
        format.html { redirect_to [@cluster, @node], notice: "Replica is being created." }
        format.json { render :show, status: :created, location: [@cluster, @replica] }
      else
        @providers = Provider.all
        format.html { render :add_replica, status: :unprocessable_entity }
        format.json { render json: @replica.errors, status: :unprocessable_entity }
      end
    end
  end

  def config_partial
    @provider = Provider.find(params[:provider_id])
    @node = @cluster.nodes.find_by_id(params[:node_id])
    
    if @node == nil
      if params[:parent_node_id].present?
        # This is a replica being created
        parent_node = @cluster.nodes.find(params[:parent_node_id])
        @replica = @cluster.nodes.new(provider: @provider, parent_node: parent_node)
        
        # Build all settings for the selected provider
        @replica.build_node_settings!
        
        # Pre-populate with parent values, except for network settings
        network_settings = %w[ip_address gateway network subnet cidr]
        parent_node.node_settings.includes(:provider_type_node_option).each do |parent_setting|
          replica_setting = @replica.node_settings.find { |rs| rs.key == parent_setting.key }
          if replica_setting && !network_settings.include?(parent_setting.key)
            replica_setting.value = parent_setting.value
          end
        end
        
        render "nodes/replica_config_display"
      else
        # Regular new node
        @node = @cluster.nodes.new(provider: @provider)
        @node.build_node_settings!
        render "nodes/config_partial"
      end
    else
      render "nodes/config_partial"
    end
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

    def replica_params
      params.expect(node: [
        :provider_id, 
        :name,
        node_settings_attributes: [
          [:id, :provider_type_node_option_id, :key, :value]
        ]
      ])
    end
end
