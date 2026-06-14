# Detects if a domain is behind Cloudflare by checking if its DNS resolves
# to known Cloudflare IP ranges. Used to skip TLS labels when Cloudflare
# handles SSL termination.
require "resolv"
require "ipaddr"

class CloudflareDetector
  # Cloudflare IPv4 and IPv6 ranges (as of 2024)
  # Source: https://www.cloudflare.com/ips/
  CF_RANGES = [
    "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22",
    "103.31.4.0/22", "141.101.64.0/18", "108.162.192.0/18",
    "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22",
    "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
    "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
    "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32",
    "2405:b500::/32", "2405:8100::/32", "2a06:98c0::/29",
    "2c0f:f248::/32"
  ].map { |cidr| IPAddr.new(cidr) }.freeze

  # Returns true if the hostname resolves to a Cloudflare IP.
  def self.cloudflare?(hostname)
    return false if hostname.blank?

    begin
      ips = Resolv.getaddresses(hostname)
      ips.any? { |ip| behind_cloudflare?(ip) }
    rescue Resolv::ResolvError
      false
    end
  end

  def self.behind_cloudflare?(ip_str)
    ip = IPAddr.new(ip_str)
    CF_RANGES.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    false
  end
end
