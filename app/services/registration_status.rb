# Determines whether a domain is registered, via the same RDAP-first→WHOIS-
# fallback ladder Tools::WhoisLookup uses (extracted here so it and
# Tools::DomainPriceChecker share one ladder instead of duplicating it).
# Never raises; returns the RDAP/WHOIS result hash with one added key.
class RegistrationStatus
  def self.check(query) = new(query).check

  def initialize(query)
    @query = query.to_s.strip
  end

  def check
    data = lookup
    data.merge(registered: registered?(data))
  end

  private

  # RDAP-first ladder. IPs and domains both get a WHOIS fallback (the whois
  # gem queries RIR WHOIS for IPs). First success wins; if both miss we keep
  # the RDAP result so its error/issues surface.
  def lookup
    rdap = ::RdapChecker.check(@query)
    return rdap if rdap[:success]

    whois = ::WhoisChecker.check(@query)
    whois[:success] ? whois : rdap.merge(error: rdap[:error] || whois[:error])
  end

  # Boolean only when the lookup succeeded; nil when it failed entirely (both
  # RDAP and WHOIS missed) — callers must check `success` before reading this,
  # rather than treating nil as a meaningful third state.
  #
  # RDAP signals "unregistered" explicitly via the rdap_not_found issue code.
  # WHOIS has no equivalent explicit signal — a WHOIS response with no
  # registrar, expiration, or creation date at all is the closest proxy for
  # "no match" and is treated as unregistered. This is a heuristic, and it is
  # deliberately scoped to WHOIS-sourced results only (source == :whois_fallback):
  # a *successful* RDAP response with the same sparse shape is a real shape for
  # a domain that IS registered (thin registry data, no rdap_not_found issue),
  # so it must NOT trip this heuristic — only checking record_type here would
  # misclassify sparse-but-registered RDAP results as unregistered. Even scoped
  # to WHOIS, a heavily privacy-redacted WHOIS record for a domain that IS
  # registered could in theory still trip it.
  def registered?(data)
    return nil unless data[:success]
    return false if not_found_issue?(data)
    return false if whois_looks_empty?(data)
    true
  end

  def not_found_issue?(data)
    Array(data[:issues]).any? { |i| (i[:code] || i["code"]) == "rdap_not_found" }
  end

  def whois_looks_empty?(data)
    data[:source] == :whois_fallback &&
      data[:registrar].blank? && data[:expiration_date].blank? && data[:creation_date].blank?
  end
end
