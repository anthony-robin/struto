require 'securerandom'
require 'pr_geohash'
require_relative 'base_event'

module Struto
  module Nips
    # Date Calendar events Notes (NIP-52).
    #
    # This kind of calendar event starts on a date and ends before a different date in the future. Its use is appropriate for all-day or multi-day events where time and time zone hold no significance. e.g., anniversary, public holidays, vacation days.
    # @see https://github.com/nostr-protocol/nips/blob/master/52.md#date-based-calendar-event
    class DateCalendarEvent < BaseEvent
      DATE_CALENDAR_KIND = 31_922

      # @param name [String] calendar event name
      # @param content [String] calendar event description
      # @param dates [Hash] the dates related options
      # @option dates [String] :start inclusive start date in ISO 8601 format (YYYY-MM-DD)
      # @option dates [String] :end exclusive end date in ISO 8601 format (YYYY-MM-DD) (optional)
      # @param location [Hash] the location related options (optional)
      # @option location [String] :location address, GPS coordinates, meeting room name, link to video call (optional)
      # @option location [Float] :latitude latitude of the event
      # @option location [Float] :longitude longitude of the event
      # @param participants [Array<String>] List of 32-bytes hex pubkey of participants (optional)
      # @param hashtags [Array<String>] List of hashtag to categorize calendar event (optional)
      # @param references [Array<String>] List of references / links to web pages, documents, video calls, recorded videos, etc. (optional)
      def initialize(name, content, dates: {}, location: {}, participants: [], hashtags: [], references: [])
        super()

        @name = name
        @content = content

        # Dates
        @start_on = dates[:start]
        @end_on = dates[:end]

        # Location
        @location = location[:location]
        @latitude = location[:latitude]
        @longitude = location[:longitude]

        # Participants
        @participants = participants

        # Hashtags
        @hashtags = hashtags

        # References
        @references = references
      end

      def call
        validate!

        {
          kind: DATE_CALENDAR_KIND,
          tags: tags,
          content: @content,
          created_at: now
        }
      end

      private

      def validate!
        raise 'Invalid name' if @name.blank?
        raise 'Invalid start date' if @start_on.blank?
      end

      def tags
        @tags = []

        # Core
        @tags.push [:d, SecureRandom.uuid]
        @tags.push [:name, @name]

        # Dates
        @tags.push [:start, @start_on.to_s]
        @tags.push [:end, @end_on.to_s] if @end_on.present?

        # Location
        @tags.push [:location, @location] if @location

        if @latitude && @longitude
          geohash = GeoHash.encode(@latitude, @longitude)

          @tags.push [:g, geohash]
        end

        # Participants
        @participants.each do |participant|
          @tags.push [:p, participant]
        end

        # Hashtags
        @hashtags.each do |hashtag|
          @tags.push [:t, hashtag]
        end

        # References
        @references.each do |reference|
          @tags.push [:r, reference]
        end

        @tags
      end
    end
  end
end
