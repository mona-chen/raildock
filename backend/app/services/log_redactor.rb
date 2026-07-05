class LogRedactor
  REDACTED = "[REDACTED]".freeze
  PATTERNS = [
    %r{(https?://[^\s:/@]+:)[^\s@]+(@)}i,
    /\bgh[opsu]_[A-Za-z0-9_]{20,}\b/,
    /\bgithub_pat_[A-Za-z0-9_]{20,}\b/,
    /((?:access_token|auth_token|token|password|secret)=)[^&\s]+/i,
    /(Authorization:\s*(?:Bearer|token)\s+)[^\s]+/i
  ].freeze

  def self.redact(value)
    text = value.to_s.dup.force_encoding("UTF-8").scrub
    PATTERNS.reduce(text) do |memo, pattern|
      memo.gsub(pattern) do
        match = Regexp.last_match
        if match.captures.compact.length >= 2
          "#{match[1]}#{REDACTED}#{match[2]}"
        elsif match.captures.compact.length == 1
          "#{match[1]}#{REDACTED}"
        else
          REDACTED
        end
      end
    end
  end
end
