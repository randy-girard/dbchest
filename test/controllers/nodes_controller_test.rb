require "test_helper"

class NodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @node = nodes(:one)
  end

  test "should get index" do
    get cluster_nodes_url(@node.cluster)
    assert_response :success
  end

  test "should get new" do
    get new_cluster_node_url(@node.cluster)
    assert_response :success
  end

  test "should create node" do
    assert_difference("Node.count") do
      post cluster_nodes_url(@node.cluster), params: { node: { cluster_id: @node.cluster_id, name: @node.name, provider_id: @node.provider_id, terraform_state: @node.terraform_state } }
    end

    assert_redirected_to cluster_node_url(Node.last.cluster, Node.last)
  end

  test "should show node" do
    get cluster_node_url(@node.cluster, @node)
    assert_response :success
  end

  test "should get edit" do
    get edit_cluster_node_url(@node.cluster, @node)
    assert_response :success
  end

  test "should update node" do
    patch cluster_node_url(@node.cluster, @node), params: { node: { cluster_id: @node.cluster_id, name: @node.name, provider_id: @node.provider_id, terraform_state: @node.terraform_state } }
    assert_redirected_to cluster_node_url(@node.cluster, @node)
  end

  test "should destroy node" do
    assert_difference("Node.count", -1) do
      delete cluster_node_url(@node.cluster, @node)
    end

    assert_redirected_to cluster_nodes_url(@node.cluster)
  end
end
