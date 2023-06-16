# frozen_string_literal: true

module GraphQL
  class Schema
    class Member
      module TypeSystemHelpers
        def initialize(*args, &block)
          super
          @to_non_null_type ||= nil
          @to_list_type ||= nil
        end
        ruby2_keywords :initialize if respond_to?(:ruby2_keywords, true)

        # @return [Schema::NonNull] Make a non-null-type representation of this type
        def to_non_null_type
          @to_non_null_type ||= GraphQL::Schema::NonNull.new(self)
        end

        # @return [Schema::List] Make a list-type representation of this type
        def to_list_type(skip_nodes_on_raise: false)
          if skip_nodes_on_raise
            @to_skipping_list_type ||= GraphQL::Schema::List.new(self, skip_nodes_on_raise: true)
          else
            @to_list_type ||= GraphQL::Schema::List.new(self)
          end
        end

        # @return [Boolean] true if this is a non-nullable type. A nullable list of non-nullables is considered nullable.
        def non_null?
          false
        end

        # @return [Boolean] true if this field's nodes should be skipped, if resolving them led to an error being raised.
        def skip_nodes_on_raise?
          false
        end

        # @return [Boolean] true if this is a list type. A non-nullable list is considered a list.
        def list?
          false
        end

        def to_type_signature
          graphql_name
        end

        # @return [GraphQL::TypeKinds::TypeKind]
        def kind
          raise GraphQL::RequiredImplementationMissingError, "No `.kind` defined for #{self}"
        end

        private

        def inherited(subclass)
          subclass.class_eval do
            @to_non_null_type ||= nil
            @to_list_type ||= nil
          end
          super
        end
      end
    end
  end
end
