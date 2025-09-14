class Cluster < ApplicationRecord
  has_many :nodes, dependent: :destroy

  def cluster_type
    "postgresql"
  end
end
