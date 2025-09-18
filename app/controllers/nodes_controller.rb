class NodesController < ApplicationController
  before_action :set_cluster
  before_action :set_providers, only: %i[ new create edit update add_replica create_replica ]
  before_action :set_node, only: %i[ show edit update destroy confirm_destroy add_replica create_replica ]

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

  # GET /nodes/1/confirm_destroy
  def confirm_destroy
    @replicas = @node.replicas
  end

  # DELETE /nodes/1 or /nodes/1.json
  def destroy
    replica_action = params[:replica_action]
    
    if @node.has_replicas? && replica_action.blank?
      redirect_to confirm_destroy_cluster_node_path(@cluster, @node), alert: "This node has replicas. Please specify what to do with them." and return
    end
    
    # Handle replicas based on user choice
    if @node.has_replicas?
      case replica_action
      when 'delete_all'
        # Delete all replicas first
        @node.replicas.each(&:deprovision!)
        notice_msg = "Node and all #{@node.replicas.count} replica(s) are being removed."
      when 'promote_first'
        # Promote first replica to primary
        first_replica = @node.replicas.first
        if first_replica
          # Detach first replica (make it primary)
          first_replica.update!(parent_node: nil)
          
          # Attach other replicas to the promoted node
          remaining_replicas = @node.replicas.reload.reject { |r| r.id == first_replica.id }
          remaining_replicas.each do |replica|
            replica.update!(parent_node: first_replica)
          end
          
          notice_msg = "Node removed. #{first_replica.name} promoted to primary with #{remaining_replicas.count} replica(s)."
        else
          notice_msg = "Node removed. No replicas were available for promotion."
        end
      when 'detach_all'
        # Detach all replicas (make them primaries)
        replica_count = @node.replicas.count
        @node.replicas.each do |replica|
          replica.update!(parent_node: nil)
        end
        notice_msg = "Node removed. #{replica_count} replica(s) converted to independent primary nodes."
      end
    else
      notice_msg = "Node is being removed."
    end
    
    @node.deprovision!

    respond_to do |format|
      format.html { redirect_to cluster_path(@cluster), notice: notice_msg, status: :see_other }
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
