# frozen_string_literal: true
require "spec_helper"

describe GraphQL::Execution::Interpreter do
  describe "skipping errored items in Lists" do
    describe "when the List's items aren't skippable" do
      it "raises the error if the list's items are required and not skippable" do
        assert_raises(ListItemSkippingTest::Boom) do
          query_list(list_field: "arrayOfRequiredItems")
        end
      end

      it "raises the error if the list's items are nullable and not skippable" do
        assert_raises(ListItemSkippingTest::Boom) do
          query_list(list_field: "arrayOfNullableItems")
        end
      end
    end

    describe "when the List's items are skippable" do
      it "skips errored items if the list's items are required and skippable" do
        items = query_list(list_field: "arrayOfRequiredSkippableItems")

        assert_equal ["Item 1", "Item 3"], items.fetch("data").fetch("arrayOfRequiredSkippableItems").map { |h| h["title"] }
      end

      it "skips errored items if the list's items are nullable and skippable" do
        items = query_list(list_field: "arrayOfNullableSkippableItems")

        assert_equal ["Item 1", "Item 3"], items.fetch("data").fetch("arrayOfNullableSkippableItems").map { |h| h["title"] }
      end
    end
  end

  describe "skipping errored items in Connections" do
    # TODO: test edges
    # How should edges be skipped? Does skipping a node mean its edge should also be skipped?

    describe "when the Connection's items aren't skippable" do
      it "raises the error if the connection's items are required and not skippable" do
        skip "on_raise API not implemented for Connections yet"

        assert_raises(ListItemSkippingTest::Boom) do
          query_connection(connection_field: "connectionOfRequiredItems")
        end
      end

      it "raises the error if the connection's items are nullable and not skippable" do
        skip "on_raise API not implemented for Connections yet"

        assert_raises(ListItemSkippingTest::Boom) do
          query_connection(connection_field: "connectionOfNullableItems")
        end
      end
    end

    describe "when the Connection's items are skippable" do
      it "skips errored items if the connection's items are required and skippable" do
        skip "on_raise API not implemented for Connections yet"
        items = query_connection(connection_field: "connectionOfRequiredSkippableItems")

        assert_equal ["Item 1", "Item 3"], items.dig("data", "connectionOfRequiredSkippableItems", "nodes").map { |h| h["title"] }
      end

      it "skips errored items if the connection's items are nullable and skippable" do
        skip "on_raise API not implemented for Connections yet"
        items = query_connection(connection_field: "connectionOfNullableSkippableItems")

        assert_equal ["Item 1", "Item 3"], items.dig("data", "connectionOfNullableSkippableItems", "nodes").map { |h| h["title"] }
      end
    end
  end

  describe "other" do
    it "dump schema" do # just to help during development
      puts ListItemSkippingTest::Schema.to_definition
    end

    it "raises ArgumentError when setting skip_nodes_on_raise on a field that isn't a list or connection" do
      c = Class.new(GraphQL::Schema::Object)

      e = assert_raises(ArgumentError) do
        c.field(:not_a_list_or_connection, String, skip_nodes_on_raise: true)
      end

      assert_match /The `skip_nodes_on_raise` option is only applicable to lists./, e.message
    end
  end

  private

  def query_list(list_field:)
    ListItemSkippingTest::Schema.execute(<<~QUERY).to_h
      query {
        #{list_field} {
          title
          subfield
        }
      }
    QUERY
  end

  def query_connection(connection_field:)
    ListItemSkippingTest::Schema.execute(<<~QUERY).to_h
      query {
        #{connection_field} {
          nodes {
            title
            subfield
          }
        }
      }
    QUERY
  end
end

module ListItemSkippingTest
  class Boom < RuntimeError
    def initialize = super("boom")
  end

  class Item < Struct.new(:title, :subfield_should_raise, keyword_init: true)
    def subfield
      if subfield_should_raise
        raise Boom
      end

      "subfield for #{title}"
    end

    def to_s = "#<Item #{title.inspect}>"
  end
end

module ListItemSkippingTest
  class ItemType < GraphQL::Schema::Object
    # connection_type_class(SkippableItemConnection)

    field :title, String, null: false
    field :should_skip, Boolean, null: false
    field :subfield, String, null: false

    def to_s = "#<GraphQL wrapper for #{object}>"

    # def self.scope_items(items, _context) = items
  end

  class ItemEdge < GraphQL::Types::Relay::BaseEdge
    node_type ItemType
  end

  class RequiredItemConnection < GraphQL::Types::Relay::BaseConnection
    node_nullable(false)
    edges_nullable(false)
    edge_nullable(false)
    has_nodes_field(true)
    edge_type ItemEdge

    # def self.inspect = to_s
    # def self.to_s = "#<GraphQL Connection #{graphql_name.inspect}>" # This crashes the debugger??
  end

  class NullableItemConnection < GraphQL::Types::Relay::BaseConnection
    node_nullable(true)
    edges_nullable(true)
    edge_nullable(true)
    has_nodes_field(true)
    edge_type ItemEdge
  end

  class RequiredSkippableItemConnection < RequiredItemConnection
    skip_nodes_on_raise(true) # Come back to this, should this property be defined here on the connection, or on the field decl where this connection type is used
    # Node type is not heritable, so we need to set it here again, otherwise you get:
    #   NoMethodError: undefined method `scope_items' for nil:NilClass
    #        /Users/alex/src/github.com/amomchilov/graphql-ruby/lib/graphql/types/relay/connection_behaviors.rb:71:in `scope_items'
    #        /Users/alex/src/github.com/amomchilov/graphql-ruby/lib/graphql/schema/field/scope_extension.rb:13:in `after_resolve'
    #        /Users/alex/src/github.com/amomchilov/graphql-ruby/lib/graphql/schema/field.rb:830:in `block (2 levels) in
    #        ...
    edge_type ItemEdge
  end

  class NullableSkippableItemConnection < NullableItemConnection
    skip_nodes_on_raise(true)
    edge_type ItemEdge # Node type is not heritable, so we need to set it here again. See above.
  end

  class QueryType < GraphQL::Schema::Object
    field :array_of_required_items,
          [ItemType, null: false],
          method: :items_list,
          null: false

    field :array_of_nullable_items,
          [ItemType, null: true],
          method: :items_list,
          null: false

    field :array_of_required_skippable_items,
          [ItemType, null: false],
          method: :items_list,
          null: false,
          skip_nodes_on_raise: true,
          on_raise: -> (err, current_object, args, context, current_field, nearest_skippable_list_item) {
            puts(:array_of_required_skippable_items)
            context.skip_from_parent_list
          }

    field :array_of_nullable_skippable_items,
          [ItemType, null: true],
          method: :items_list,
          null: false,
          skip_nodes_on_raise: true,
          on_raise: -> (err, current_object, args, context, current_field, nearest_skippable_list_item) {
            puts(:array_of_required_skippable_items)
            context.skip_from_parent_list
          }

    field :connection_of_required_items,
          RequiredItemConnection,
          method: :items_connection,
          null: false

    field :connection_of_nullable_items,
          NullableItemConnection,
          method: :items_connection,
          null: false

    field :connection_of_required_skippable_items,
          RequiredSkippableItemConnection,
          method: :items_connection,
          null: false

    field :connection_of_nullable_skippable_items,
          NullableSkippableItemConnection,
          method: :items_connection,
          null: false

    def items_list
      [
        Item.new(title: "Item 1", subfield_should_raise: false),
        Item.new(title: "Item 2 💣", subfield_should_raise: true),
        Item.new(title: "Item 3", subfield_should_raise: false),
      ]
    end

    def items_connection
      items_list
    end

    # TODO: why are these necessary? Shouldn't `method: :items_list` be enough?
    alias_method :array_of_required_items, :items_list
    alias_method :array_of_nullable_items, :items_list
    alias_method :array_of_required_skippable_items, :items_list
    alias_method :array_of_nullable_skippable_items, :items_list
    alias_method :connection_of_required_items, :items_connection
    alias_method :connection_of_nullable_items, :items_connection
    alias_method :connection_of_required_skippable_items, :items_connection
    alias_method :connection_of_nullable_skippable_items, :items_connection
  end

  class Schema < GraphQL::Schema
    query QueryType
  end
end
