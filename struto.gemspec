$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'struto/version'

Gem::Specification.new do |spec|
  spec.name          = 'struto'
  spec.version       = Struto::VERSION
  spec.summary       = 'A Ruby library to interact with the Nostr protocol'
  spec.description   = 'Struto is a Ruby library to interact with the Nostr protocol. At this stage the focus is the creation of public events and private encrypted messages.'
  spec.authors       = ['Anthony Robin']
  spec.homepage      = 'https://github.com/anthony-robin/struto'
  spec.licenses      = ['MIT']
  spec.files         = Dir.glob('{bin/*,lib/**/*,[A-Z]*}')
  spec.platform      = Gem::Platform::RUBY
  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.required_ruby_version = '>= 2.6'

  spec.add_dependency 'base64', '~> 0.1.1'
  spec.add_dependency 'bech32', '~> 1.3.0'
  spec.add_dependency 'bip-schnorr', '~> 0.4.0'
  spec.add_dependency 'json', '~> 2.6.2'
  spec.add_dependency 'pr_geohash', '~> 1.0.0'
  spec.add_dependency 'unicode-emoji', '~> 3.3.1'
  spec.add_dependency 'websocket-client-simple', '~> 0.6.0'
end
