require 'shellwords'

module MB
  module Sound
    # An audio output stream that opens the `jack-stdin` command in a pipe and
    # writes 32-bit little-endian float data to it, for playing directly to a
    # jackd audio network.
    class JackOutput < MB::Sound::IOOutput
      attr_reader :channels, :ports, :buffer_size, :rate

      # Initializes a JACK output stream for the given list of port names (pass
      # `nil` for a port name to leave that port disconnected).  Alternatively,
      # you may pass an integer for +ports+ to allocate that many
      # disconnected ports.
      #
      # The sample rate given should match whatever rate jackd is using.
      #
      # Note: as a starting point, set the buffer size equal to the hop size
      # used in any processing algorithms.  This needs to be at least twice the
      # jackd buffer size.
      #
      # Examples:
      #
      # Playing to the first two system output channels:
      #     MB::Sound::JackOutput.new(ports: ['system:playback_1', 'system:playback_2'])
      #
      # Creating 8 unconnected output ports:
      #     MB::Sound::JackOutput.new(ports: 8)
      def initialize(ports:, rate: 48000, buffer_size: 2048)
        ports = [nil] * ports if ports.is_a?(Integer)
        @ports = ports
        @rate = rate
        @channels = @ports.size
        @buffer_size = buffer_size&.to_i || 2048
        ports = @ports.map { |n| (n || "invalid port #{rand(100000)}").shellescape }.join(' ')

        @pipe = IO.popen(["sh", "-c", "jack-stdin -p 25 -L -e floating-point -q -S #{@buffer_size} #{ports}"], "w")

        super(@pipe, channels)
      end
    end
  end
end