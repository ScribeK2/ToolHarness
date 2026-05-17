require "dnsruby"

class SubdomainScanner
  TIMEOUT = 5.seconds

  # Common subdomains to check
  COMMON_SUBDOMAINS = %w[
    www
    mail
    webmail
    email
    smtp
    pop
    imap
    ftp
    sftp
    ssh
    vpn
    remote
    admin
    portal
    login
    secure
    api
    dev
    staging
    test
    beta
    app
    mobile
    m
    shop
    store
    blog
    news
    support
    help
    docs
    cdn
    static
    assets
    media
    img
    images
    video
    ns1
    ns2
    dns
    mx
    mx1
    mx2
    autodiscover
    autoconfig
    cpanel
    whm
    plesk
    dashboard
    panel
    server
    host
    cloud
    backup
    db
    database
    mysql
    sql
    postgres
    redis
    mongo
    elasticsearch
    kibana
    grafana
    prometheus
    jenkins
    gitlab
    git
    svn
    ci
    status
    monitor
    nagios
    zabbix
  ].freeze

  def self.scan(domain, subdomains: COMMON_SUBDOMAINS)
    new(domain).scan(subdomains)
  end

  def initialize(domain)
    @domain = domain.to_s.strip.downcase
  end

  def scan(subdomains = COMMON_SUBDOMAINS)
    cache_key = "subdomains:#{@domain}"
    cached_result = Rails.cache.read(cache_key)
    return cached_result if cached_result

    result = {
      success: true,
      domain: @domain,
      found: [],
      not_found: [],
      errors: [],
      scanned_at: Time.current.iso8601
    }

    resolver = Dnsruby::Resolver.new(
      nameserver: "8.8.8.8",
      timeout: TIMEOUT
    )

    subdomains.each do |subdomain|
      fqdn = "#{subdomain}.#{@domain}"

      begin
        response = resolver.query(fqdn, Dnsruby::Types::A)
        a_records = response.answer
          .select { |r| r.type == Dnsruby::Types::A }
          .map(&:address).map(&:to_s)

        if a_records.any?
          result[:found] << {
            subdomain: subdomain,
            fqdn: fqdn,
            a_records: a_records,
            type: categorize_subdomain(subdomain)
          }
        else
          result[:not_found] << subdomain
        end
      rescue Dnsruby::NXDomain
        result[:not_found] << subdomain
      rescue Dnsruby::ResolvTimeout
        result[:errors] << { subdomain: subdomain, error: "Timeout" }
      rescue StandardError => e
        result[:errors] << { subdomain: subdomain, error: e.message }
      end
    end

    # Sort found subdomains by category
    result[:found].sort_by! { |s| [category_order(s[:type]), s[:subdomain]] }

    # Cache results for 6 hours
    Rails.cache.write(cache_key, result, expires_in: 6.hours)

    result
  end

  private

  def categorize_subdomain(subdomain)
    case subdomain
    when "www", "m", "mobile"
      "web"
    when "mail", "webmail", "email", "smtp", "pop", "imap", "mx", "mx1", "mx2", "autodiscover", "autoconfig"
      "email"
    when "ftp", "sftp", "ssh", "vpn", "remote"
      "access"
    when "admin", "portal", "login", "secure", "cpanel", "whm", "plesk", "dashboard", "panel"
      "admin"
    when "api", "dev", "staging", "test", "beta"
      "development"
    when "app", "shop", "store", "blog", "news"
      "application"
    when "support", "help", "docs", "status"
      "support"
    when "cdn", "static", "assets", "media", "img", "images", "video"
      "cdn"
    when "ns1", "ns2", "dns"
      "dns"
    when "server", "host", "cloud", "backup"
      "infrastructure"
    when "db", "database", "mysql", "sql", "postgres", "redis", "mongo", "elasticsearch"
      "database"
    when "kibana", "grafana", "prometheus", "jenkins", "gitlab", "git", "svn", "ci", "monitor", "nagios", "zabbix"
      "devops"
    else
      "other"
    end
  end

  def category_order(category)
    {
      "web" => 0,
      "email" => 1,
      "admin" => 2,
      "application" => 3,
      "api" => 4,
      "development" => 5,
      "support" => 6,
      "cdn" => 7,
      "dns" => 8,
      "access" => 9,
      "infrastructure" => 10,
      "database" => 11,
      "devops" => 12,
      "other" => 99
    }[category] || 99
  end
end

