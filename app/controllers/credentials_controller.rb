class CredentialsController < ApplicationController
  before_action :set_cluster
  before_action :set_node
  before_action :set_credential, only: %i[ show edit update destroy ]

  # GET /credentials or /credentials.json
  def index
    @credentials = @node.credentials.all
  end

  # GET /credentials/1 or /credentials/1.json
  def show
  end

  # GET /credentials/new
  def new
    # Check if this is a replica with automatic user replication
    if @node.replica? && @node.parent_node.present?
      database_type_handler = @node.database_type_handler
      if database_type_handler.respond_to?(:users_replicate_automatically?) && database_type_handler.users_replicate_automatically?
        redirect_to [ @cluster, @node ], alert: "Cannot create credentials on a replica node. Create credentials on the primary node instead."
        return
      end
    end

    @credential = @node.credentials.new
  end

  # GET /credentials/1/edit
  def edit
  end

  # POST /credentials or /credentials.json
  def create
    @credential = @node.credentials.new(credential_params)

    respond_to do |format|
      if @credential.save
        @credential.provision!
        format.html { redirect_to [ @cluster, @node ], notice: "Credential was successfully created." }
        format.json { render :show, status: :created, location: [ @cluster, @node, @credential ] }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @credential.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /credentials/1 or /credentials/1.json
  def update
    respond_to do |format|
      if @credential.update(credential_params)
        format.html { redirect_to [ @cluster, @node ], notice: "Credential was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: [ @cluster, @node, @credential ] }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @credential.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /credentials/1 or /credentials/1.json
  def destroy
    if @credential.default_credential?
      respond_to do |format|
        format.html { redirect_to [ @cluster, @node ], alert: "Cannot delete the default credential.", status: :see_other }
        format.json { render json: { error: "Cannot delete the default credential" }, status: :unprocessable_entity }
      end
      return
    end

    if @credential.is_replicated?
      respond_to do |format|
        format.html { redirect_to [ @cluster, @node ], alert: "Cannot delete replicated credentials. Delete the credential from the primary node instead.", status: :see_other }
        format.json { render json: { error: "Cannot delete replicated credentials" }, status: :unprocessable_entity }
      end
      return
    end

    @credential.deprovision!

    respond_to do |format|
      format.html { redirect_to [ @cluster, @node ], notice: "Credential was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    def set_cluster
      @cluster = Cluster.find(params.expect(:cluster_id))
    end

    def set_node
      @node = @cluster.nodes.find(params.expect(:node_id))
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_credential
      @credential = @node.credentials.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def credential_params
      params.expect(credential: [ :username, :password ])
    end
end
