class Cluster < ApplicationRecord
  has_many :nodes, dependent: :destroy
end
