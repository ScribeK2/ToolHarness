require "test_helper"

class Tools::DomainPriceCheckerTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  UNREGISTERED = { success: true, registered: false, registrar: nil, error: nil, issues: [] }.freeze
  REGISTERED   = { success: true, registered: true, registrar: "GoDaddy.com, LLC", error: nil, issues: [] }.freeze
  BOTH_FAILED  = { success: false, registered: nil, error: "no endpoint", issues: [] }.freeze

  CHEAP_COM      = { tld: "com", registration: 9.68, renewal: 10.37, transfer: 9.68 }.freeze
  EXPENSIVE_GAME = { tld: "game", registration: 599.98, renewal: 599.98, transfer: 599.98 }.freeze

  test "unregistered domain under cap: within_budget issue plus the standing pricing caveat" do
    RegistrationStatus.stub(:check, UNREGISTERED) do
      PorkbunPriceList.stub(:price_for, CHEAP_COM) do
        result = Tools::DomainPriceChecker.new.execute(domain: "example.com")
        assert result.success
        assert_equal false, result.data[:registered]
        assert_equal "Registration price", result.data[:headline_label]
        assert_equal 9.68, result.data[:headline_price]
        assert_equal true, result.data[:within_budget]
        assert_equal %w[within_budget standard_pricing_caveat], result.issues.map { |i| i[:code] }
        assert_equal "info", result.issues.first[:severity]
      end
    end
  end

  test "unregistered domain over cap: critical over_budget issue plus the standing pricing caveat" do
    RegistrationStatus.stub(:check, UNREGISTERED) do
      PorkbunPriceList.stub(:price_for, EXPENSIVE_GAME) do
        result = Tools::DomainPriceChecker.new.execute(domain: "example.game", budget_cap: "25")
        assert result.success
        assert_equal false, result.data[:within_budget]
        assert_equal %w[over_budget standard_pricing_caveat], result.issues.map { |i| i[:code] }
        assert_equal "critical", result.issues.first[:severity]
      end
    end
  end

  test "registered domain under cap: premium-unconfirmed warning replaces plain within_budget, no duplicate caveat" do
    RegistrationStatus.stub(:check, REGISTERED) do
      PorkbunPriceList.stub(:price_for, CHEAP_COM) do
        result = Tools::DomainPriceChecker.new.execute(domain: "example.com")
        assert result.success
        assert_equal true, result.data[:registered]
        assert_equal "GoDaddy.com, LLC", result.data[:registrar]
        assert_equal "Transfer price", result.data[:headline_label]
        assert_equal 9.68, result.data[:headline_price]
        assert_equal true, result.data[:within_budget]
        # premium_pricing_unconfirmed already IS the caveat for this case — no
        # separate standard_pricing_caveat issue appended (would be a near-
        # duplicate of the same warning).
        assert_equal ["premium_pricing_unconfirmed"], result.issues.map { |i| i[:code] }
        assert_equal "warning", result.issues.first[:severity]
      end
    end
  end

  test "registered domain over cap on a legitimately expensive TLD: clean critical verdict plus caveat" do
    RegistrationStatus.stub(:check, REGISTERED) do
      PorkbunPriceList.stub(:price_for, EXPENSIVE_GAME) do
        result = Tools::DomainPriceChecker.new.execute(domain: "example.game")
        assert result.success
        assert_equal false, result.data[:within_budget]
        assert_equal %w[over_budget standard_pricing_caveat], result.issues.map { |i| i[:code] }
        assert_equal "critical", result.issues.first[:severity]
      end
    end
  end

  test "price unavailable when the TLD isn't in Porkbun's list, plus the standing pricing caveat" do
    RegistrationStatus.stub(:check, REGISTERED) do
      PorkbunPriceList.stub(:price_for, nil) do
        result = Tools::DomainPriceChecker.new.execute(domain: "example.zzz")
        assert result.success
        assert_nil result.data[:headline_price]
        assert_nil result.data[:within_budget]
        assert_equal %w[price_unavailable standard_pricing_caveat], result.issues.map { |i| i[:code] }
        assert_equal "warning", result.issues.first[:severity]
      end
    end
  end

  test "blank domain fails without hitting the network" do
    RegistrationStatus.stub(:check, ->(*) { flunk "should not be called for a blank domain" }) do
      result = Tools::DomainPriceChecker.new.execute(domain: "")
      refute result.success
    end
  end

  test "fails outright when registration status lookup fails entirely" do
    RegistrationStatus.stub(:check, BOTH_FAILED) do
      result = Tools::DomainPriceChecker.new.execute(domain: "example.com")
      refute result.success
      assert_equal "no endpoint", result.error
    end
  end

  test "budget_cap defaults to 25 when blank" do
    RegistrationStatus.stub(:check, UNREGISTERED) do
      PorkbunPriceList.stub(:price_for, CHEAP_COM) do
        result = Tools::DomainPriceChecker.new.execute(domain: "example.com", budget_cap: "")
        assert_equal 25.0, result.data[:budget_cap]
      end
    end
  end

  test "budget_cap defaults to 25 when negative or non-numeric" do
    RegistrationStatus.stub(:check, UNREGISTERED) do
      PorkbunPriceList.stub(:price_for, CHEAP_COM) do
        result = Tools::DomainPriceChecker.new.execute(domain: "example.com", budget_cap: "-5")
        assert_equal 25.0, result.data[:budget_cap]

        result2 = Tools::DomainPriceChecker.new.execute(domain: "example.com", budget_cap: "abc")
        assert_equal 25.0, result2.data[:budget_cap]
      end
    end
  end

  test "custom budget_cap is honored" do
    RegistrationStatus.stub(:check, UNREGISTERED) do
      PorkbunPriceList.stub(:price_for, EXPENSIVE_GAME) do
        result = Tools::DomainPriceChecker.new.execute(domain: "example.game", budget_cap: "700")
        assert_equal 700.0, result.data[:budget_cap]
        assert_equal true, result.data[:within_budget]
      end
    end
  end
end
