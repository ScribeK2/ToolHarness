require "dnsruby"

class PropagationChecker
  TIMEOUT = 10.seconds   # per-resolver dnsruby timeout
  JOIN_TIMEOUT = TIMEOUT + 1.second   # outer Thread#join cap, must exceed TIMEOUT

  SEVERITY_CRITICAL = "critical"
  SEVERITY_WARNING  = "warning"
  SEVERITY_INFO     = "info"

  RESOLVERS = [
    { id: "google-1",      ip: "8.8.8.8",         operator: "Google",        region: "Global anycast" },
    { id: "google-2",      ip: "8.8.4.4",         operator: "Google",        region: "Global anycast" },
    { id: "cloudflare-1",  ip: "1.1.1.1",         operator: "Cloudflare",    region: "Global anycast" },
    { id: "cloudflare-2",  ip: "1.0.0.1",         operator: "Cloudflare",    region: "Global anycast" },
    { id: "quad9",         ip: "9.9.9.9",         operator: "Quad9",         region: "CH (anycast)"   },
    { id: "opendns-1",     ip: "208.67.222.222",  operator: "OpenDNS",       region: "Global anycast" },
    { id: "opendns-2",     ip: "208.67.220.220",  operator: "OpenDNS",       region: "Global anycast" },
    { id: "verisign",      ip: "64.6.64.6",       operator: "Verisign",      region: "US"             },
    { id: "yandex",        ip: "77.88.8.8",       operator: "Yandex",        region: "RU"             },
    { id: "adguard",       ip: "94.140.14.14",    operator: "AdGuard",       region: "CY/Global"      },
    { id: "comodo",        ip: "8.26.56.26",      operator: "Comodo",        region: "US"             },
    { id: "neustar",       ip: "156.154.70.1",    operator: "Neustar",       region: "US"             },
    { id: "dns-watch",     ip: "84.200.69.80",    operator: "DNS.WATCH",     region: "DE"             },
    { id: "level3",        ip: "4.2.2.1",         operator: "Level3",        region: "US"             },
    { id: "alternate",     ip: "76.76.19.19",     operator: "Alternate",     region: "US"             },
    { id: "cleanbrowsing", ip: "185.228.168.9",   operator: "CleanBrowsing", region: "Global"         },
    { id: "norton",        ip: "199.85.126.10",   operator: "Norton",        region: "US"             },
    { id: "uncensoreddns", ip: "91.239.100.100",  operator: "UncensoredDNS", region: "DK"             },
    { id: "freenom",       ip: "80.80.80.80",     operator: "Freenom",       region: "NL"             },
    { id: "controld",      ip: "76.76.2.0",       operator: "Control D",     region: "Global anycast" }
  ].freeze

  SUPPORTED_TYPES = %w[A AAAA MX NS CNAME TXT SOA CAA].freeze

  def self.check(domain, record_type:, resolver_factory: nil)
    new(domain, record_type: record_type, resolver_factory: resolver_factory).check
  end

  def initialize(domain, record_type:, resolver_factory: nil)
    @domain = domain.to_s.strip.downcase
    @record_type = record_type.to_s.upcase
    @resolver_factory = resolver_factory || method(:build_real_resolver)
  end

  def check
    # Implemented in Task 9.
    raise NotImplementedError
  end

  private

  def build_real_resolver(address)
    Dnsruby::Resolver.new(nameserver: address, timeout: TIMEOUT)
  end

  def normalize_values(record_type, answer)
    rrs = answer_for_type(record_type, answer)
    case record_type
    when "A", "AAAA"
      rrs.map { |r| r.address.to_s }.sort
    when "MX"
      rrs
        .sort_by { |r| [r.preference.to_i, r.exchange.to_s] }
        .map { |r| "#{r.preference} #{strip_dot(r.exchange)}" }
    when "NS"
      rrs.map { |r| strip_dot(r.nsdname).downcase }.sort
    when "CNAME"
      rrs.map { |r| strip_dot(r.rdata).downcase }.sort
    when "TXT"
      rrs.map { |r| Array(r.strings).join }.sort
    when "SOA"
      rrs.map { |r| "#{strip_dot(r.mname)} #{strip_dot(r.rname)} #{r.serial}" }
    when "CAA"
      rrs.map { |r| "#{r.flags} #{r.tag} #{r.value}" }.sort
    else
      []
    end
  end

  def answer_for_type(record_type, answer)
    target = dnsruby_type(record_type)
    Array(answer).select { |r| r.type == target }
  end

  def dnsruby_type(record_type)
    Dnsruby::Types.const_get(record_type)
  end

  def strip_dot(host)
    host.to_s.sub(/\.\z/, "")
  end

  def query_one(entry)
    base = entry.merge(values: [], ttl: nil, error: nil)
    started = monotonic_ms

    resolver = @resolver_factory.call(entry[:ip])
    response = resolver.query(@domain, dnsruby_type(@record_type))
    rrs = answer_for_type(@record_type, response.answer)

    base.merge(
      status: :ok,
      values: normalize_values(@record_type, response.answer),
      ttl: rrs.map { |r| r.ttl.to_i }.min,
      latency_ms: monotonic_ms - started
    )
  rescue Dnsruby::NXDomain => e
    base.merge(status: :nxdomain, error: short_error(e), latency_ms: monotonic_ms - started)
  rescue Dnsruby::ServFail => e
    base.merge(status: :servfail, error: short_error(e), latency_ms: monotonic_ms - started)
  rescue Dnsruby::Refused => e
    base.merge(status: :refused, error: short_error(e), latency_ms: monotonic_ms - started)
  rescue Dnsruby::ResolvTimeout, Timeout::Error => e
    base.merge(status: :timeout, error: short_error(e), latency_ms: monotonic_ms - started)
  rescue Dnsruby::ResolvError, StandardError => e
    base.merge(status: :error, error: short_error(e), latency_ms: monotonic_ms - started)
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  end

  def short_error(e)
    msg = e.message.to_s
    "#{e.class.name.demodulize}: #{msg.length > 120 ? msg[0, 117] + '...' : msg}"
  end
end
