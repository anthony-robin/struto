require_relative 'base_event'

module Struto
  module Nips
    # Zap Poll event (NIP-69)
    #
    # A zap poll note is a nostr event for conducting paid polls—herein
    # referred to simply as 'polls'. A poll presents two or more voting
    # options, which participants may vote on by sending regular zap events
    # which include an additional `poll_option` vote tag.
    # @see https://github.com/nostr-protocol/nips/pull/320
    class PollEvent < BaseEvent
      POLL_EVENT_KIND = 6969

      # @param content [String] note content content
      # @param poll_options [Array<String>] list of poll options
      # @param metadata [Hash] list of poll metadata
      # @option metadata [String] :value_minimum the minimum amount of satoshis to pay
      # @option metadata [String] :value_maximum the maximum amount of satoshis to pay
      # @option metadata [String] :closed_at the timestamp to close the poll at
      # @option metadata [String] :reference the parent note to link to
      def initialize(content, poll_options, metadata = {})
        super()

        @content = content
        @poll_options = poll_options
        @metadata = metadata
      end

      def call
        validate!

        {
          kind: POLL_EVENT_KIND,
          tags: tags,
          content: @content,
          created_at: now
        }
      end

      private

      def validate!
        raise 'Invalid options' unless @poll_options.is_a?(Array) && @poll_options.count >= 2
      end

      def tags
        @tags = []

        @poll_options.each_with_index do |option, index|
          @tags.push [:poll_option, index.to_s, option]
        end

        @tags.push [:value_minimum, metadata[:value_minimum].to_s] unless metadata[:value_minimum].blank?
        @tags.push [:value_maximum, metadata[:value_maximum].to_s] unless metadata[:value_maximum].blank?
        @tags.push [:closed_at, metadata[:closed_at].to_s] unless metadata[:closed_at].blank?
        @tags.push [:e, metadata[:reference]] unless metadata[:reference].blank?

        @tags
      end

      def metadata
        @metadata.compact.slice(
          :value_minimum, :value_maximum, :closed_at, :reference
        )
      end
    end
  end
end
