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
