require "openssl"

FactoryBot.define do
  factory :server do
    name { Faker::Internet.domain_word }
    host { Faker::Internet.ip_v4_address }
    ssh_key { OpenSSL::PKey::EC.generate("prime256v1").to_pem }
    status { :connected }
    dokku_version { "0.35.13" }
    docker_version { "26.1.0" }
    os { "Ubuntu 22.04" }
    uptime { "45d 12h" }
    disk_used { 38 }
    disk_total { 100 }
    memory_used { 62 }
    memory_total { 128 }
    default_proxy { "traefik" }
    organization
  end
end
