# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name    = 'redis_pipeline_batcher'
  spec.version = '0.0.1'
  spec.authors = ['Erwan Thomas']
  spec.email   = ['janotus@maen.fr']

  spec.summary = 'Redis pipeline batcher'

  # Prevent pushing this gem to RubyGems.org.
  spec.metadata['allowed_push_host'] = 'none'

  spec.files = Dir[File.join('lib', '**', '*')]

  spec.require_paths = ['lib']
end
