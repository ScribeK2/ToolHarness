module Tools
  class DomainPriceChecker
    include ToolHarness::Tool

    DEFAULT_BUDGET_CAP = 25.0

    def self.tool_name = "Domain Price Checker"
    def self.category = :domain
    def self.description = "Standard TLD registration/transfer pricing (bundled Porkbun price-list " \
      "snapshot) for a domain, badged against a configurable budget cap — built to check transfer-in " \
      "cost against a free-domain promo before promising it to a client."
    def self.form_fields = { domain: :text, budget_cap: :number }
    def self.input_type = :domain
    def self.cacheable? = false
    def self.timeout = 30

    def execute(params)
      query = params[:domain].to_s.strip
      return blank_domain_result if query.blank?

      cap    = parse_budget_cap(params[:budget_cap])
      status = ::RegistrationStatus.check(query)
      return failed_status_result(status) unless status[:success]

      price = ::PorkbunPriceList.price_for(query)
      data  = build_data(query, status, price, cap)

      ToolHarness::Result.new(
        success: true,
        tool: self.class.tool_name,
        data: data,
        issues: build_issues(data),
        summary: build_summary(data)
      )
    end

    private

    def blank_domain_result
      ToolHarness::Result.new(
        success: false, tool: self.class.tool_name,
        error: "Enter a domain to check.", summary: "No domain provided."
      )
    end

    def failed_status_result(status)
      ToolHarness::Result.new(
        success: false, tool: self.class.tool_name,
        error: status[:error], summary: "Registration lookup failed: #{status[:error] || 'unknown error'}."
      )
    end

    def parse_budget_cap(raw)
      value = raw.to_s.to_f
      value.positive? ? value : DEFAULT_BUDGET_CAP
    end

    def build_data(query, status, price, cap)
      registered     = status[:registered]
      headline_price = price && (registered ? price[:transfer] : price[:registration])

      {
        domain: query,
        tld: price&.dig(:tld),
        registered: registered,
        registrar: registered ? status[:registrar] : nil,
        pricing: {
          registration: price&.dig(:registration),
          renewal: price&.dig(:renewal),
          transfer: price&.dig(:transfer),
          as_of: price&.dig(:as_of)
        },
        headline_price: headline_price,
        headline_label: registered ? "Transfer price" : "Registration price",
        budget_cap: cap,
        within_budget: headline_price.nil? ? nil : headline_price <= cap
      }
    end

    # One verdict issue, plus the standing pricing-source caveat on every run
    # except when the verdict issue already IS that caveat (premium pricing
    # unconfirmed on a registered domain) — appending both there would just
    # repeat the same warning twice.
    def build_issues(data)
      verdict = verdict_issue(data)
      return [verdict] if verdict[:code] == "premium_pricing_unconfirmed"
      [verdict, standard_pricing_caveat_issue]
    end

    def verdict_issue(data)
      return price_unavailable_issue if data[:headline_price].nil?
      return over_budget_issue(data) unless data[:within_budget]

      data[:registered] ? premium_unconfirmed_issue(data) : within_budget_issue(data)
    end

    def standard_pricing_caveat_issue
      {
        severity: "info", code: "standard_pricing_caveat",
        title: "Standard Pricing Only",
        message: "Standard TLD pricing only — premium/aftermarket domains can cost significantly more " \
          "than shown; this source can't detect per-domain premium pricing.",
        recommendation: nil
      }
    end

    def price_unavailable_issue
      {
        severity: "warning", code: "price_unavailable",
        title: "Price Unavailable",
        message: "This domain's TLD isn't in the bundled Porkbun price list, or the price snapshot " \
          "(config/porkbun_pricing.json) is missing.",
        recommendation: "Check pricing manually with your registrar, or refresh the snapshot with " \
          "script/refresh-porkbun-pricing."
      }
    end

    def over_budget_issue(data)
      {
        severity: "critical", code: "over_budget",
        title: "Over Budget",
        message: "#{data[:headline_label]} (#{money(data[:headline_price])}) exceeds the " \
          "#{money(data[:budget_cap])} cap.",
        recommendation: "This domain is over the free-domain promo cap — flag it to the client before proceeding."
      }
    end

    def premium_unconfirmed_issue(data)
      {
        severity: "warning", code: "premium_pricing_unconfirmed",
        title: "Premium Pricing Unconfirmed",
        message: "Standard transfer pricing (#{money(data[:headline_price])}) is within the " \
          "#{money(data[:budget_cap])} cap, but this source can't detect premium/aftermarket pricing.",
        recommendation: "Confirm this isn't a premium domain before promising the promo cap — premium " \
          "pricing is the most likely way a transfer exceeds it."
      }
    end

    def within_budget_issue(data)
      {
        severity: "info", code: "within_budget",
        title: "Within Budget",
        message: "#{data[:headline_label]} (#{money(data[:headline_price])}) is within the " \
          "#{money(data[:budget_cap])} cap.",
        recommendation: nil
      }
    end

    def build_summary(data)
      "#{data[:domain]} — #{domain_status_word(data)} — #{price_summary(data)}#{budget_cap_summary(data)}"
    end

    def domain_status_word(data)
      return "UNREGISTERED" unless data[:registered]
      data[:registrar].present? ? "REGISTERED (#{data[:registrar]})" : "REGISTERED"
    end

    def price_summary(data)
      return "price unavailable" unless data[:headline_price]
      "#{data[:headline_label].downcase} #{money(data[:headline_price])}"
    end

    def budget_cap_summary(data)
      case data[:within_budget]
      when true  then " — WITHIN #{money(data[:budget_cap])} CAP"
      when false then " — OVER #{money(data[:budget_cap])} CAP"
      else ""
      end
    end

    def money(amount) = format("$%.2f", amount)
  end
end
