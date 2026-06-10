module ToolHarness
  class Registry
    class << self
      def tools
        @tools ||= {}
      end

      def engines
        @engines ||= {}
      end

      def register_tool(klass)
        key = klass.name.demodulize.underscore.to_sym
        tools[key] = klass
      end

      def register(name, engine)
        engines[name.to_sym] = engine
      end

      def find_tool(key)
        tools[key.to_sym]
      end

      # Result partials for retired tool keys — keeps old runs rendering with
      # full fidelity after the tool class is deleted. Keys without an entry
      # fall back to the generic ResultPresenter sections.
      LEGACY_PARTIALS = {
        "dns_propagation" => "results/tools/dns_propagation"
      }.freeze

      def legacy_partial(tool_key)
        LEGACY_PARTIALS[tool_key.to_s]
      end

      def categories
        tools.values.group_by(&:category)
      end

      def tools_for_category(cat)
        tools.values.select { |t| t.category == cat.to_sym }
      end

      def tools_for_input(input_type)
        tools.values.select { |t| t.input_type == input_type.to_sym }
      end

      def all_categories
        tools.values.map(&:category).uniq.sort
      end

      def auto_discover!
        Dir[Rails.root.join("app/services/tools/**/*.rb")].sort.each { |f| require f }
      end

      def reset!
        @tools = {}
        @engines = {}
      end
    end
  end
end
