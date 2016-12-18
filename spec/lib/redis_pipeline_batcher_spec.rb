# frozen_string_literal: true

RSpec.describe RedisPipelineBatcher do
  let(:conn) { double }
  let(:size) { 10 }
  let(:handler) { double }

  subject { described_class.new(conn, size) }

  before(:each) do
    allow(conn).to receive(:pipelined).and_yield
    allow(handler).to receive(:call)
  end

  describe '.new' do
    context 'without handler' do
      it 'does not yield the batcher' do
        expect { |b|
          described_class.new(conn, size, &b)
        }.not_to yield_control
      end
    end

    context 'with a handler' do
      it 'yields the batcher' do
        expect { |b|
          described_class.new(conn, size, handler, &b)
        }.to yield_with_args(instance_of(described_class))
      end
    end
  end

  describe '.call' do
    let(:batcher) { double }

    it 'initializes and calls a batcher in one step' do
      expect(described_class).to receive(:new).with(conn, size).and_return(batcher)
      expect(batcher).to receive(:call)

      described_class.call(conn, size)
    end

    context 'without handler' do
      it 'does not yield the batcher' do
        expect { |b|
          described_class.call(conn, size, &b)
        }.not_to yield_control
      end
    end

    context 'with a handler' do
      it 'yields the batcher' do
        expect { |b|
          described_class.call(conn, size, handler, &b)
        }.to yield_with_args(instance_of(described_class))
      end
    end
  end

  describe 'arbitrary messages' do
    it 'accepts messages handled by its connection' do
      allow(conn).to receive(:get)
      allow(conn).to receive(:set)

      expect(subject).to respond_to(:get)
      expect(subject).to respond_to(:set)

      expect(subject).not_to respond_to(:random_dummy_message)
    end
  end

  describe 'modes' do
    let(:size) { 2 }

    let(:divisible_messages) do
      {
        [:set, %w(foo bar)] => rand,
        [:get, %w(foo)]     => rand,
        [:set, %w(bar baz)] => rand,
        [:mock_that_yield, %w(bar), proc {}] => rand,
      }.to_a
    end

    let(:not_divisible_messages) do
      {
        [:set, %w(foo bar)] => rand,
        [:get, %w(foo)]     => rand,
        [:set, %w(bar baz)] => rand,
        [:del, %w(bar)]     => rand,
        [:mock_that_yield, %w(bar), proc {}] => rand,
      }.to_a
    end

    let(:messages) { divisible_messages }

    def send_messages_to(batcher)
      messages.each do |(message, args, block), _|
        batcher.public_send(message, *args, &block)
      end
    end

    def expect_no_conn_messages
      messages.each do |(message, _, block), _|
        expect(conn).not_to receive(message).with(any_args)
      end
    end

    def expect_conn_messages
      messages.each_slice(size) do |batch|
        expect(conn).to receive(:pipelined).ordered.and_yield

        batch.each do |(message, args, block), response|
          expect(conn).to receive(message).with(*args, &block).ordered.and_return(response)
        end
      end
    end

    def expect_handler_messages
      results = []

      messages.each_slice(size) do |batch|
        results << batch.map { |_, response| response }
      end

      results.each do |partial_results|
        expect(handler).to receive(:call).with(partial_results)
      end
    end

    context 'when not given a handler' do
      context 'when not yet called' do
        it 'does not send messages to its connection' do
          expect_no_conn_messages
          send_messages_to(subject)
        end
      end

      context 'when called' do
        def self.it_runs_batches_when_called
          it 'runs batches when called' do
            expect_conn_messages
            send_messages_to(subject)
            subject.call
          end
        end

        context 'when batches are the same size' do
          let(:messages) { divisible_messages }

          it_runs_batches_when_called
        end

        context 'when batches are not the same size' do
          let(:messages) { not_divisible_messages }

          it_runs_batches_when_called
        end
      end
    end

    context 'when given a handler' do
      def self.it_yields_the_batcher_and_runs_batches_as_soon_as_possible
        it 'yields the batcher and runs batches as soon as possible' do
          expect_conn_messages
          expect_handler_messages

          described_class.new(conn, size, handler) do |batcher|
            send_messages_to(batcher)
          end
        end
      end

      context 'when batches are the same size' do
        let(:messages) { divisible_messages }

        it_yields_the_batcher_and_runs_batches_as_soon_as_possible
      end

      context 'when batches are not the same size' do
        let(:messages) { not_divisible_messages }

        it_yields_the_batcher_and_runs_batches_as_soon_as_possible
      end
    end
  end
end
