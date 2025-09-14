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
        format.html { redirect_to @cluster, notice: "Credential was successfully created." }
        format.json { render :show, status: :created, location: @credential }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @credential.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /credentials/1 or /credentials/1.json
  def update
    respond_to do |format|
      if @credential.update(credential_params)
        format.html { redirect_to @cluster, notice: "Credential was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @credential }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @credential.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /credentials/1 or /credentials/1.json
  def destroy
    @credential.deprovision!

    respond_to do |format|
      format.html { redirect_to @cluster, notice: "Credential was successfully destroyed.", status: :see_other }
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
      params.expect(credential: [ :username ])
    end
end
