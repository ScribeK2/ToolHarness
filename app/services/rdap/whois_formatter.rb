require "ipaddr"
require "time"

module Rdap
  # Renders a parsed RDAP response hash as flat whois-style `Label: value` text,
  # matching the field set the `rdap -w` CLI emits. Pure transform over data
  # already fetched by RdapChecker — no network, no host deps (AppImage-safe).
  module WhoisFormatter
    module_function

    def format(response, record_type:)
      case record_type.to_sym
      when :ip     then format_ip(response)
      when :domain then format_domain(response)
      else raise ArgumentError, "Unknown record_type: #{record_type}"
      end
    end

    def format_domain(d)
      d ||= {}
      lines = []
      add(lines, "Domain Name", d["ldhName"])
      add(lines, "Registry Domain ID", d["handle"])
      reg = entity_with_role(d, "registrar")
      add(lines, "Registrar", vcard(reg, "fn"))
      add(lines, "Registrar IANA ID", public_id(reg, "IANA Registrar ID"))
      add(lines, "Registrar URL", link_href(reg))
      add(lines, "Updated Date", event_date(d, "last changed"))
      add(lines, "Creation Date", event_date(d, "registration"))
      add(lines, "Registry Expiry Date", event_date(d, "expiration"))
      Array(d["status"]).each { |s| add(lines, "Domain Status", epp_status(s)) }
      Array(d["nameservers"]).each { |n| add(lines, "Name Server", n["ldhName"].to_s.downcase) }
      add(lines, "DNSSEC", dnssec(d))
      registrant = entity_with_role(d, "registrant")
      add(lines, "Registrant Organization", vcard(registrant, "org"))
      add(lines, "Registrant Name", vcard(registrant, "fn"))
      add(lines, "Registrant Email", vcard(registrant, "email"))
      abuse = abuse_entity(reg)
      add(lines, "Abuse Contact Email", vcard(abuse, "email"))
      add(lines, "Abuse Contact Phone", vcard(abuse, "tel"))
      lines.join("\n")
    end

    def format_ip(d)
      d ||= {}
      lines = []
      start_a = d["startAddress"]
      end_a   = d["endAddress"]
      add(lines, "NetRange", ([start_a, end_a].all?(&:present?) ? "#{start_a} - #{end_a}" : nil))
      add(lines, "CIDR", cidr(start_a, end_a))
      add(lines, "NetName", d["name"])
      add(lines, "NetType", d["type"])
      add(lines, "Country", d["country"])
      org = entity_with_role(d, "registrant")
      add(lines, "Organization", vcard(org, "fn") || vcard(org, "org"))
      add(lines, "RegDate", event_date(d, "registration"))
      add(lines, "Updated", event_date(d, "last changed"))
      abuse = entity_with_role(d, "abuse")
      add(lines, "Abuse Contact Email", vcard(abuse, "email"))
      add(lines, "Parent", d["parentHandle"])
      lines.join("\n")
    end

    # --- helpers ---

    def add(lines, label, value)
      v = value.to_s.strip
      lines << "#{label}: #{v}" unless v.empty?
    end

    def entity_with_role(d, role)
      Array(d && d["entities"]).find { |e| Array(e["roles"]).include?(role) }
    end

    # A registrar entity may carry a nested abuse entity.
    def abuse_entity(reg)
      Array(reg && reg["entities"]).find { |e| Array(e["roles"]).include?("abuse") }
    end

    def public_id(entity, type)
      pid = Array(entity && entity["publicIds"]).find { |p| p["type"].to_s == type }
      pid && pid["identifier"]
    end

    def link_href(entity)
      link = Array(entity && entity["links"]).find { |l| l["href"].present? }
      link && link["href"]
    end

    def event_date(d, action)
      ev = Array(d && d["events"]).find { |e| e["eventAction"].to_s.casecmp?(action) }
      return nil unless ev && ev["eventDate"]
      Time.parse(ev["eventDate"]).iso8601 rescue ev["eventDate"]
    end

    def dnssec(d)
      sd = d["secureDNS"]
      return nil unless sd.is_a?(Hash) && !sd["delegationSigned"].nil?
      sd["delegationSigned"] ? "signedDelegation" : "unsigned"
    end

    # RDAP status (RFC 8056, space-lowercase) -> EPP camelCase like `rdap -w`.
    # Non-conforming registries sometimes send the EPP form directly; pass those
    # through unchanged rather than mangling them to lowercase.
    EPP_OVERRIDES = { "active" => "ok" }.freeze
    def epp_status(status)
      s = status.to_s.strip
      return EPP_OVERRIDES[s] if EPP_OVERRIDES.key?(s)
      return s if s !~ /\s/ && s =~ /[A-Z]/ # already camelCase (single word, has uppercase)
      words = s.split(/\s+/)
      ([words.first&.downcase] + words.drop(1).map(&:capitalize)).join
    end

    def cidr(start_a, end_a)
      return nil unless start_a.present? && end_a.present?
      lo = IPAddr.new(start_a)
      hi = IPAddr.new(end_a)
      bits = lo.ipv6? ? 128 : 32
      prefix = bits - Math.log2(hi.to_i - lo.to_i + 1).ceil
      "#{start_a}/#{prefix}"
    rescue StandardError
      nil
    end

    # vcardArray = ["vcard", [ [name, params, type, value], ... ]]
    def vcard(entity, field)
      arr = entity && entity["vcardArray"]
      return nil unless arr.is_a?(Array) && arr[1].is_a?(Array)
      row = arr[1].find { |r| r.is_a?(Array) && r[0].to_s.casecmp?(field) }
      val = row && row[3]
      val.is_a?(Array) ? val.join(" ").strip : val
    end
  end
end
