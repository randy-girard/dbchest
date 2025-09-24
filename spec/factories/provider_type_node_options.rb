FactoryBot.define do
  factory :provider_type_node_option do
    association :provider_type
    key { "template_storage" }
    label { "Storage" }
    required { true }

    trait :template do
      key { "template_template" }
      label { "Template" }
    end

    trait :disk_size do
      key { "disk_size" }
      label { "Disk Size" }
    end

    trait :node do
      key { "node" }
      label { "Node" }
    end

    trait :ip_address do
      key { "ip_address" }
      label { "IP Address" }
    end

    trait :gateway do
      key { "gateway" }
      label { "Gateway" }
    end

    trait :not_required do
      required { false }
    end
  end
end
