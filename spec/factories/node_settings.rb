FactoryBot.define do
  factory :node_setting do
    association :node
    association :provider_type_node_option
    key { "template_storage" }
    value { "local-lvm" }
    
    trait :template do
      association :provider_type_node_option, :template
      key { "template_template" }
      value { "ubuntu-22.04-template" }
    end
    
    trait :disk_size do
      association :provider_type_node_option, :disk_size
      key { "disk_size" }
      value { "20G" }
    end
    
    trait :ip_address do
      association :provider_type_node_option, :ip_address
      key { "ip_address" }
      value { "192.168.1.100" }
    end
    
    trait :gateway do
      association :provider_type_node_option, :gateway
      key { "gateway" }
      value { "192.168.1.1" }
    end
  end
end
