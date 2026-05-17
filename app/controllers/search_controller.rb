class SearchController < ApplicationController
  DOMAIN_REGEX = /\A[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?)+\z/
  TICKET_REGEX = /\A[A-Za-z]+-\d+\z/
  EMAIL_REGEX  = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  def show
    @raw_query = params[:q].to_s.strip
    @type, @canonical = classify(@raw_query)
    @applicable = applicable_tools(@type)
    @prefill_field, @prefill_value = prefill_for(@type, @canonical)
  end

  private

  # Returns [type_symbol, canonical_value]. For email, canonical strips the
  # local part down to the domain so domain-based tools can use it.
  def classify(query)
    return [:empty, nil] if query.empty?
    return [:ticket, query] if query.match?(TICKET_REGEX)
    if query.match?(EMAIL_REGEX)
      return [:email, query.downcase.split("@", 2).last]
    end

    addr = ip_address(query)
    return [:ipv4, query] if addr&.ipv4?
    return [:ipv6, query] if addr&.ipv6?

    return [:domain, query.downcase] if query.match?(DOMAIN_REGEX)

    [:unknown, query]
  end

  def ip_address(s)
    IPAddr.new(s)
  rescue IPAddr::InvalidAddressError
    nil
  end

  # Maps detected type to a filtered subset of registered tools.
  # :host-typed tools accept both domains and IPs; :domain-typed tools accept
  # only DNS-resolvable names. Ticket has its own input field.
  def applicable_tools(type)
    case type
    when :ticket
      ToolHarness::Registry.tools.select { |_, k| k.form_fields.key?(:ticket_id) }
    when :email, :domain
      ToolHarness::Registry.tools.select { |_, k| k.form_fields.key?(:domain) }
    when :ipv4
      host_input_tools
    when :ipv6
      host_input_tools.reject { |key, _| key == :blacklist }  # Blacklist DNSBLs are IPv4-only
    else
      {}
    end
  end

  def host_input_tools
    ToolHarness::Registry.tools.select { |_, k| k.input_type == :host }
  end

  def prefill_for(type, canonical)
    case type
    when :ticket                          then [:ticket_id, canonical]
    when :email, :domain, :ipv4, :ipv6    then [:domain, canonical]
    else [nil, nil]
    end
  end
end
