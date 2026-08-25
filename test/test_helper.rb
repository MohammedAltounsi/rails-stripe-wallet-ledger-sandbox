ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run serially. The suite asserts global ledger invariants (Posting.sum == 0,
    # account balances) against one shared DB, so thread parallelism — which
    # Minitest auto-enables past ~50 tests — makes runs collide and bleed state.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
