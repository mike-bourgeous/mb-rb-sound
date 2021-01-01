require 'midi-message'
require 'nibbler'

module MB
  module Sound
    # An oscillator that can generate different wave types.  This can be used
    # to generate sound, or as an LFO (low-frequency oscillator).  All
    # oscillators should start at 0 (except for e.g. square, which doesn't have
    # a zero), and rise first before falling, unless a phase offset is
    # specified.
    #
    # An exponential distortion can be applied to the output before or after
    # values are scaled to the desired output range.
    class Oscillator
      RAND = Random.new
      WAVE_TYPES = [:sine, :square, :triangle, :ramp]

      # See #initialize; this is used to make negative powers more useful.
      NEGATIVE_POWER_SCALE = {
        sine: 0.01,
        triangle: 0.01,
        ramp: 0.01,
        square: 1.0,
      }

      # Note that is used as tuning reference
      TUNE_NOTE = 69 # A4

      # Frequency that the tuning reference should be
      TUNE_FREQ = 440

      # Calculates a frequency in Hz for the given MIDI note number and
      # detuning in cents.
      def self.calc_freq(note_number, detune_cents = 0)
        TUNE_FREQ * 2 ** ((note_number + detune_cents / 100.0 - TUNE_NOTE) / 12.0)
      end

      # Calculates a fractional MIDI note number for the given frequency,
      # assuming equal temperament.
      def self.calc_number(frequency_hz)
        12.0 * Math.log2(frequency_hz / TUNE_FREQ) + TUNE_NOTE
      end

      attr_accessor :advance, :wave_type, :pre_power, :post_power, :range
      attr_reader :phase, :frequency

      # TODO: maybe use a clock provider instead of +advance+?  The challenge is
      # that floating point accuracy goes down as a shared clock advances, and
      # every oscillator needs its own internal phase if the phase is to be kept
      # within 0..2pi.  Maybe also separate the oscillator from the phase
      # counter?

      # Initializes a low frequency oscillator with the given +wave_type+,
      # +frequency+, and +range+.  The +advance+ parameter makes it easier to
      # control the speed of a large number of oscillators.
      #
      # To avoid complex results for non-integer +pre_power+ and +post_power+
      # values, the absolute value of the oscillator is taken, the power applied,
      # and then the original sign restored.  For negative powers, values are
      # scaled down by the value from NEGATIVE_POWER_SCALE and clamped to -1..1
      # after pre_power is applied.  See the .safe_power function.
      #
      # +wave_type+ - One of the symbols from WAVE_TYPES.
      # +frequency+ - The number of cycles for every 2*pi/+advance+ calls to
      #               #sample.  Pass (2 * Math::PI / sample_rate) to +:advance+
      #               for this +frequency+ to be in Hz.
      # +phase+ - The initial offset of the oscillator (typically 0 to 2*pi).
      # +range+ - The output range of the oscillator (defaults to -1..1).
      # +pre_power+ - The oscillator output will be raised to this power before scaling to +range+.
      # +post_power+ - The oscillator output will be raised to this power after scaling to +range+.
      # +advance+ - The base amount to increment the internal phase for each call
      #             to #sample.  This should be (2 * Math::PI / sample_rate)
      #             for audio oscillators.
      # +random_advance+ - The internal phase is incremented by a random value up to this amount on top of +advance+.
      def initialize(wave_type, frequency: 1.0, phase: 0.0, range: nil, pre_power: 1.0, post_power: 1.0, advance: Math::PI / 24000.0, random_advance: 0.0)
        unless WAVE_TYPES.include?(wave_type)
          raise "Invalid wave type #{wave_type.inspect}; only #{WAVE_TYPES.map(&:inspect).join(', ')} are supported"
        end
        @wave_type = wave_type

        self.frequency = frequency

        raise "Invalid phase #{phase.inspect}" unless phase.is_a?(Numeric)
        @phase = phase.to_f % (2.0 * Math::PI)
        @phi = @phase

        raise "Invalid range #{range.inspect}" unless range.nil? || range.first.is_a?(Numeric)
        @range = range

        raise "Invalid pre_power #{pre_power.inspect}" unless pre_power.is_a?(Numeric)
        @pre_power = pre_power.to_f

        raise "Invalid post_power #{post_power.inspect}" unless post_power.is_a?(Numeric)
        @post_power = post_power.to_f

        raise "Invalid advance #{advance.inspect}" unless advance.is_a?(Numeric)
        @advance = advance.to_f

        raise "Invalid random advance #{random_advance.inspect}" unless random_advance.is_a?(Numeric)
        @random_advance = random_advance
      end

      # Changes the phase offset for this oscillator.
      def phase=(phase)
        @phi += (phase - @phase)
        @phase = phase
        while @phi < 0
          @phi += 2.0 * Math::PI
        end
        while @phi >= 2.0 * Math::PI
          @phi -= 2.0 * Math::PI
        end
      end

      def frequency=(frequency)
        raise "Invalid frequency #{frequency.inspect}" unless frequency.is_a?(Numeric) || frequency.respond_to?(:sample)

        @frequency = frequency
        frequency = frequency.respond_to?(:sample) ? frequency.sample : frequency.to_f
        @note_number = Oscillator.calc_number(frequency)
      end

      # Sets the oscillator's frequency to the given MIDI note number.
      def number=(note_number)
        @note_number = note_number
        self.frequency = Oscillator.calc_freq(note_number)
      end

      # Updates the oscillator baesd on the given MIDI event, which should be
      # an event type from the midi-nibbler gem.  Uses NoteOn to change the
      # frequency, NoteOff to silence the oscillator, and CC#1 (mod wheel) to
      # control the oscillator power (distortion).
      #
      # TODO: Allow changing waveform
      # TODO: Maybe this belongs in a different class
      def handle_midi(midi_event)
        case midi_event
        when MIDIMessage::NoteOn
          self.number = midi_event.note
          amplitude = midi_event.velocity * 0.5 / 127 + 0.01
          self.range = -amplitude..amplitude

        when MIDIMessage::NoteOff
          # Only turn off the oscillator if the note off event matches the
          # current frequency (this allows playing legato; multiple note on and
          # note off events will be received, but only the note off event for
          # the current note will count)
          if midi_event.note == @note_number
            self.range = 0..0
          end

        when MIDIMessage::ControlChange
          if midi_event.index == 1
            # Mod wheel
            self.post_power = MB::Sound::M.scale(midi_event.value, 0..127, 1.0..0.1)
          end
        end
      end

      # Returns the value of the oscillator for a given phase between 0 and 2pi.
      # The output value ranges from -1 to 1.
      def oscillator(phi)
        case @wave_type
        when :sine
          s = Math.sin(phi)

        when :triangle
          if phi < 0.5 * Math::PI
            # Initial rise from 0..1 in 0..pi/2
            s = phi * 2.0 / Math::PI
          elsif phi < 1.5 * Math::PI
            # Fall from 1..-1 in pi/2..3pi/2
            s = 2.0 - phi * 2.0 / Math::PI
          else
            # Final rise from -1..0 in 3pi/2..2pi
            s = phi * 2.0 / Math::PI - 4.0
          end

        when :square
          if phi < Math::PI
            s = 1.0
          else
            s = -1.0
          end

        when :ramp
          if phi < Math::PI
            # Initial rise from 0..1 in 0..pi
            s = phi / Math::PI
          else
            # Final rise from -1..0 in pi..2pi
            s = phi / Math::PI - 2.0
          end

        else
          raise "Invalid wave type #{@wave_type.inspect}"
        end

        s = MB::Sound::M.safe_power(s, @pre_power) if @pre_power != 1.0
        s = MB::Sound::M.clamp(-1.0, 1.0, s * NEGATIVE_POWER_SCALE[@wave_type]) if @pre_power < 0

        s
      end

      # Returns the next value of the oscillator and advances the internal phase.
      def sample(count = nil)
        if count
          return Numo::SFloat.zeros(count).map { sample }
        end

        result = oscillator(@phi)

        result = MB::Sound::M.scale(result, -1.0..1.0, @range) if @range
        result = MB::Sound::M.safe_power(result, @post_power) if @post_power != 1.0

        advance = @advance
        advance += RAND.rand(@random_advance) if @random_advance != 0

        # TODO: this doesn't modulate strongly enough
        # FM attempt:
        # fm = Oscillator.new(
        #   :sine,
        #   frequency: Oscillator.new(:sine, frequency: 220, range: -970..370, advance: Math::PI / 24000),
        #   advance: Math::PI / 24000
        # )
        freq = @frequency
        freq = freq.sample if freq.respond_to?(:sample)

        @phi += freq * advance
        while @phi >= 2.0 * Math::PI
          @phi -= 2.0 * Math::PI
        end

        result
      end
    end
  end
end
