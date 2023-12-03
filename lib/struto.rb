require_relative 'custom_addr'
require_relative 'crypto_tools'
require 'ecdsa'
require 'schnorr'
require 'json'
require 'base64'
require 'bech32'
require 'unicode/emoji'
require 'websocket-client-simple'
require 'struto/nips/time_calendar_event'
require 'struto/nips/date_calendar_event'
require 'struto/nips/poll_event'

# * Ruby library to interact with the Nostr protocol

module Struto
  class Nostr
    include CryptoTools

    attr_reader :private_key, :public_key, :pow_difficulty_target, :nip26_delegation_tag

    def self.to_hex(bech32_key)
      public_addr = CustomAddr.new(bech32_key)
      public_addr.to_scriptpubkey
    end

    def self.to_bech32(hex_key, hrp)
      custom_addr = CustomAddr.new
      custom_addr.scriptpubkey = hex_key
      custom_addr.hrp = hrp
      custom_addr.addr
    end

    def self.verify_delegation_signature(delegatee_pubkey, tag)
      delegation_message_sha256 = Digest::SHA256.hexdigest("nostr:delegation:#{delegatee_pubkey}:#{tag[2]}")
      Schnorr.valid_sig?(Array(delegation_message_sha256).pack('H*'), Array(tag[1]).pack('H*'), Array(tag[3]).pack('H*'))
    end

    def initialize(key)
      hex_private_key = if key[:private_key]&.include?('nsec')
        Struto::Nostr.to_hex(key[:private_key])
      else
        key[:private_key]
      end

      hex_public_key = if key[:public_key]&.include?('npub')
        Struto::Nostr.to_hex(key[:public_key])
      else
        key[:public_key]
      end

      if hex_private_key
        @private_key = hex_private_key
        group = ECDSA::Group::Secp256k1
        @public_key = group.generator.multiply_by_scalar(private_key.to_i(16)).x.to_s(16).rjust(64, '0')
      elsif hex_public_key
        @public_key = hex_public_key
      else
        raise 'Missing private or public key'
      end
    end

    def keys
      keys = { public_key: @public_key }
      keys[:private_key] = @private_key if @private_key
      keys
    end

    def bech32_keys
      bech32_keys = { public_key: Struto::Nostr.to_bech32(@public_key, 'npub') }
      bech32_keys[:private_key] = Struto::Nostr.to_bech32(@private_key, 'nsec') if @private_key
      bech32_keys
    end

    def sign_event(event)
      raise 'Invalid pubkey' unless event[:pubkey].is_a?(String) && event[:pubkey].size == 64
      raise 'Invalid created_at' unless event[:created_at].is_a?(Integer)
      raise 'Invalid kind' unless (0..31_999).cover?(event[:kind])
      raise 'Invalid tags' unless event[:tags].is_a?(Array)
      raise 'Invalid content' unless event[:content].is_a?(String)

      serialized_event = [
        0,
        event[:pubkey],
        event[:created_at],
        event[:kind],
        event[:tags],
        event[:content]
      ]

      serialized_event_sha256 = nil
      if @pow_difficulty_target
        nonce = 1
        loop do
          nonce_tag = ['nonce', nonce.to_s, @pow_difficulty_target.to_s]
          nonced_serialized_event = serialized_event.clone
          nonced_serialized_event[4] = nonced_serialized_event[4] + [nonce_tag]
          serialized_event_sha256 = Digest::SHA256.hexdigest(JSON.dump(nonced_serialized_event))
          if match_pow_difficulty?(serialized_event_sha256)
            event[:tags] << nonce_tag
            break
          end
          nonce += 1
        end
      else
        serialized_event_sha256 = Digest::SHA256.hexdigest(JSON.dump(serialized_event))
      end

      private_key = Array(@private_key).pack('H*')
      message = Array(serialized_event_sha256).pack('H*')
      event_signature = Schnorr.sign(message, private_key).encode.unpack1('H*')

      event[:id] = serialized_event_sha256
      event[:sig] = event_signature
      event
    end

    def build_event(payload)
      if @nip26_delegation_tag
        payload[:tags] = [] unless payload[:tags]
        payload[:tags] << @nip26_delegation_tag
      end

      event = sign_event(payload)
      ['EVENT', event]
    end

    # Metadata (NIP-01 / NIP-24)
    # @see https://github.com/nostr-protocol/nips/blob/master/01.md
    # @see https://github.com/nostr-protocol/nips/blob/master/24.md
    #
    # @param metadata [Hash] list of nostr account metadata
    # @option metadata [String] :name
    # @option metadata [String] :display_name
    # @option metadata [String] :about the profile description
    # @option metadata [String] :picture the profile picture
    # @option metadata [String] :banner the profile banner
    # @option metadata [String] :nip05 the NIP-05 verification address
    # @option metadata [String] :lud16 the lightning network address
    # @option metadata [String] :website
    def build_metadata_event(metadata = {})
      data = metadata.slice(
        :name, :display_name, :about, :picture,
        :banner, :nip05, :lud16, :website
      )

      event = {
        pubkey: @public_key,
        created_at: now,
        kind: 0,
        tags: [],
        content: data.to_json
      }

      build_event(event)
    end

    def build_note_event(text, channel_key = nil)
      event = {
        pubkey: @public_key,
        created_at: now,
        kind: channel_key ? 42 : 1,
        tags: channel_key ? [['e', channel_key]] : [],
        content: text
      }

      build_event(event)
    end

    def build_recommended_relay_event(relay)
      raise 'Invalid relay' unless relay.start_with?('wss://', 'ws://')

      event = {
        pubkey: @public_key,
        created_at: now,
        kind: 2,
        tags: [],
        content: relay
      }

      build_event(event)
    end

    def build_contact_list_event(contacts)
      event = {
        pubkey: @public_key,
        created_at: now,
        kind: 3,
        tags: contacts.map { |c| ['p'] + c },
        content: ''
      }

      build_event(event)
    end

    def build_dm_event(text, recipient_public_key)
      encrypted_text = CryptoTools.aes_256_cbc_encrypt(@private_key, recipient_public_key, text)

      event = {
        pubkey: @public_key,
        created_at: now,
        kind: 4,
        tags: [['p', recipient_public_key]],
        content: encrypted_text
      }

      build_event(event)
    end

    def build_deletion_event(events, reason = '')
      event = {
        pubkey: @public_key,
        created_at: now,
        kind: 5,
        tags: events.map { |e| ['e', e] },
        content: reason
      }

      build_event(event)
    end

    def build_reaction_event(reaction, event, author)
      raise 'Invalid reaction' unless ['+', '-'].include?(reaction) || reaction.match?(Unicode::Emoji::REGEX)
      raise 'Invalid author' unless event.is_a?(String) && event.size == 64
      raise 'Invalid event' unless author.is_a?(String) && author.size == 64

      event = {
        pubkey: @public_key,
        created_at: now,
        kind: 7,
        tags: [['e', event], ['p', author]],
        content: reaction
      }

      build_event(event)
    end

    def build_poll_event(content, poll_options, metadata = {})
      instance = Struto::Nips::PollEvent.new(content, poll_options, metadata)

      event = instance.call
      event[:pubkey] = @public_key

      build_event(event)
    end

    def build_time_calendar_event(name, content, timestamps: {}, location: {}, participants: [], hashtags: [], references: [])
      instance = Struto::Nips::TimeCalendarEvent.new(
        name, content,
        timestamps: timestamps,
        location: location,
        participants: participants,
        hashtags: hashtags,
        references: references
      )

      event = instance.call
      event[:pubkey] = @public_key

      build_event(event)
    end

    def build_date_calendar_event(name, content, dates: {}, location: {}, participants: [], hashtags: [], references: [])
      instance = Struto::Nips::DateCalendarEvent.new(
        name, content,
        dates: dates,
        location: location,
        participants: participants,
        hashtags: hashtags,
        references: references
      )

      event = instance.call
      event[:pubkey] = @public_key

      build_event(event)
    end

    def decrypt_dm(event)
      data = event[1]
      sender_public_key = data[:pubkey] == @public_key ? data[:tags][0][1] : data[:pubkey]
      encrypted = data[:content].split('?iv=')[0]
      iv = data[:content].split('?iv=')[1]
      CryptoTools.aes_256_cbc_decrypt(@private_key, sender_public_key, encrypted, iv)
    end

    def get_delegation_tag(delegatee_pubkey, conditions)
      delegation_message_sha256 = Digest::SHA256.hexdigest("nostr:delegation:#{delegatee_pubkey}:#{conditions}")
      signature = Schnorr.sign(Array(delegation_message_sha256).pack('H*'), Array(@private_key).pack('H*')).encode.unpack1('H*')
      [
        'delegation',
        @public_key,
        conditions,
        signature
      ]
    end

    def set_delegation(tag)
      @nip26_delegation_tag = tag
    end

    def reset_delegation
      @nip26_delegation_tag = nil
    end

    def build_req_event(filters)
      ['REQ', SecureRandom.random_number.to_s, filters]
    end

    def build_close_event(subscription_id)
      ['CLOSE', subscription_id]
    end

    def build_notice_event(message)
      ['NOTICE', message]
    end

    def match_pow_difficulty?(event_id)
      @pow_difficulty_target.nil? || @pow_difficulty_target == [event_id].pack('H*').unpack1('B*').index('1')
    end

    def set_pow_difficulty_target(difficulty)
      @pow_difficulty_target = difficulty
    end

    def now
      Time.now.utc.to_i
    end

    def post_event(event, relay)
      response = nil
      ws = WebSocket::Client::Simple.connect(relay)

      ws.on :open do
        ws.send event.to_json
      end

      ws.on :message do |msg|
        response = JSON.parse(msg.data.force_encoding('UTF-8'))
        ws.close
      end

      ws.on :error do |e|
        puts "WebSocket Error => #{e.message}"
        ws.close
      end

      sleep 0.1 while response.nil?

      response
    end
  end
end
