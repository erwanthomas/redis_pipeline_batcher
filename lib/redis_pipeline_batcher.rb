# frozen_string_literal: true

class RedisPipelineBatcher
  def self.call(conn, size, handler = nil)
    if handler
      new(conn, size, handler, &Proc.new)
    else
      new(conn, size).call
    end
  end

  def initialize(conn, size, handler = nil)
    @conn = conn
    @batch_max_size = size
    @batch_handler = handler

    _reset

    if @batch_handler
      yield(self)

      _handle_final_results
    end
  end

  def call(flat: false)
    results = @batches.map do |batch|
      @conn.pipelined do
        # we use map here instead of each as it is easier to write tests that way
        batch.map do |(name, args, block)|
          @conn.public_send(name, *args, &block)
        end
      end
    end

    _reset

    flat ? results.tap(&:flatten!) : results
  end

  def method_missing(name, *args, &block)
    if @conn.respond_to?(name)
      _handle_call(name, args, block)
    else
      super
    end
  end

  def respond_to_missing?(name, _)
    @conn.respond_to?(name)
  end

  private

  def _reset
    @batches = []
    @batch_size = nil
  end

  def _handle_call(*args)
    if _new_batch_needed?
      _append_command_to_new_batch(args)
    else
      _append_command_to_current_batch(args)
    end

    _handle_partial_results
  end

  def _batch_full?
    @batch_size == @batch_max_size
  end

  def _new_batch_needed?
    @batches.empty? || _batch_full?
  end

  def _append_command_to_current_batch(args)
    @batches.last << args
    @batch_size += 1
  end

  def _append_command_to_new_batch(args)
    @batches << [args]
    @batch_size = 1
  end

  def _handler_wants_partial_results?
    @batch_handler.respond_to?(:call) && _batch_full?
  end

  def _handle_partial_results
    return unless _handler_wants_partial_results?
    @batch_handler.call(call(flat: true))
  end

  def _handler_wants_final_results?
    @batch_handler.respond_to?(:call) && !@batches.empty?
  end

  def _handle_final_results
    return unless _handler_wants_final_results?
    @batch_handler.call(call(flat: true))
  end
end
