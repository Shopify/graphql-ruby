# frozen_string_literal: true

module GraphQL
  class Schema
    class Field
      class DefaultResolverTracker
        attr_reader :counts_by_field
        attr_reader :strategy_by_field

        def initialize
          @counts_by_field = Hash.new do |h, k|
            h[k] = Hash.new do |h2, k2|
              h2[k2] = 0
            end
          end
          @strategy_by_field = Hash.new do |h, k|
            h[k] = Set.new
          end
        end

        def track(field, strategy)
          @counts_by_field[field.path][strategy] += 1
          @strategy_by_field[strategy] << field.path
        end
      end
    end
  end
end
