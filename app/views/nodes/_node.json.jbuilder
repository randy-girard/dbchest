json.extract! node, :id, :cluster_id, :provider_id, :name, :terraform_state, :created_at, :updated_at
json.url cluster_node_url([@cluster, node], format: :json)
