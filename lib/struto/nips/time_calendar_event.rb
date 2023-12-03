require 'securerandom'
require 'pr_geohash'
require_relative 'base_event'

module Struto
  module Nips
    # Time Calendar events Notes (NIP-52).
    #
    # This kind of calendar event spans between a start time and end time.
    # @see https://github.com/nostr-protocol/nips/blob/master/52.md#time-based-calendar-event
    class TimeCalendarEvent < BaseEvent
      TIME_CALENDAR_KIND = 31_923

      # @param name [String] calendar event name
      # @param content [String] calendar event description
      # @param timestamps [Hash] the time related options
      # @option timestamps [DateTime, Time, Integer] :start inclusive start Unix timestamp in seconds
      # @option timestamps [DateTime, Time, Integer] :end exclusive end Unix timestamp in seconds (optional)
      # @option timestamps [String] :start_tzid time zone of the start timestamp, as defined by the IANA Time Zone Database
      # @option timestamps [String] :end_tzid time zone of the end timestamp, as defined by the IANA Time Zone Database
      # @option location [String] :location address, GPS coordinates, meeting room name, link to video call (optional)
      # @option location [Float] :latitude latitude of the event
      # @option location [Float] :longitude longitude of the event
      # @param participants [Array<String>] List of 32-bytes hex pubkey of participants (optional)
      # @param hashtags [Array<String>] List of hashtag to categorize calendar event (optional)
      # @param references [Array<String>] List of references / links to web pages, documents, video calls, recorded videos, etc. (optional)
      def initialize(name, content, timestamps: {}, location: {}, participants: [], hashtags: [], references: [])
        super()

        @name = name
        @content = content

        # Timestamps
        @start_at = timestamps[:start]
        @end_at = timestamps[:end]
        @start_tzid = timestamps[:start_tzid]
        @end_tzid = timestamps[:end_tzid]

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
          kind: TIME_CALENDAR_KIND,
          tags: tags,
          content: @content,
          created_at: now
        }
      end

      private

      def validate!
        raise 'Invalid name' if @name.blank?
        raise 'Invalid start date' if @start_at.blank?
      end

      def tags
        @tags = []

        # Core
        @tags.push [:d, SecureRandom.uuid]
        @tags.push [:name, @name]

        # Timestamps
        @tags.push [:start, @start_at.to_i.to_s]
        @tags.push [:start_tzid, @start_tzid] if @start_tzid.present?

        if @end_at.present?
          @tags.push [:end, @end_at.to_i.to_s]

          if @end_tzid.present?
            @tags.push [:end_tzid, @end_tzid]
          elsif @start_tzid.present?
            @tags.push [:end_tzid, @start_tzid]
          end
        end

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
