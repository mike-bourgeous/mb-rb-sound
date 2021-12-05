module MB
  module Sound
    # Adds methods to any class that implements a :sample method to build
    # signal generation and processing graphs.  In combination with Tone, Note,
    # and the helper methods in MB::Sound, this creates a DSL that can quickly
    # generate complex sounds.
    #
    # Examples:
    #     # From within bin/sound.rb
    #     play F1.at(-6.db).fm(F2.at(300) * adsr(0, 0.1, 0.0, 0.5, auto_release: false)) * adsr(0, 0, 1, 0.0, auto_release: 0.25)
    module ArithmeticMixin
      # Creates a mixer that adds this mixer's output to +other+.  Part of a
      # DSL experiment for building up a signal graph.
      def +(other)
        other.or_for(nil) if other.respond_to?(:or_for) # Default to playing forever
        Mixer.new([self, other])
      end

      # Creates a mixer that subtracts +other+ from this mixer's output.  Part
      # of a DSL experiment for building up a signal graph.
      def -(other)
        other.or_for(nil) if other.respond_to?(:or_for) # Default to playing forever
        Mixer.new([self, [other, -1]])
      end

      # Creates a multiplier that multiplies +other+ by this mixer's output.
      # Part of a DSL experiment for building up a signal graph.
      def *(other)
        other.or_for(nil) if other.respond_to?(:or_for) # Default to playing forever
        other.or_at(1) if other.respond_to?(:or_at) # Keep amplitude high
        Multiplier.new([self, other])
      end

      # Applies the given filter (creating the filter if given a filter type)
      # to this sample source or sample chain.  If given a filter type, then a
      # dynamically updating filter is created where teh cutoff and quality are
      # controlled by the given sample sources (e.g. numeric value, tone
      # generator, audio input, or ADSR envelope).
      #
      # Defaults to generating a low-pass filter if given a frequency in Hz.
      #
      # Example:
      #     # Simple low-pass filter at 1200Hz center frequency
      #     MB::Sound.play 500.hz.ramp.filter(1200.hz)
      #
      #     # Low-pass filter with center frequency sweeping between 500 and 1000 Hz
      #     MB::Sound.play 500.hz.ramp.filter(cutoff: 0.2.hz.at(500), quality: 4)
      #
      #     # High-pass filter controlled by envelopes
      #     MB::Sound.play 500.hz.ramp.filter(:highpass, frequency: adsr() * 1000 + 100, quality: adsr() * -5 + 6)
      def filter(filter_or_type = :lowpass, cutoff: nil, quality: nil, in_place: true, rate: 48000)
        f = filter_or_type
        f = f.hz if f.is_a?(Numeric)
        f = f.lowpass if f.is_a?(Tone)

        case
        when f.is_a?(Symbol)
          raise 'Cutoff frequency must be given when creating a filter by type' if cutoff.nil?

          quality = quality || 0.5 ** 0.5
          f = MB::Sound::Filter::Cookbook.new(filter_or_type, rate, 1, quality: 1)
          MB::Sound::Filter::Cookbook::CookbookWrapper.new(filter: f, audio: self, cutoff: cutoff, quality: quality)

        when f.respond_to?(:wrap)
          if cutoff || quality
            raise 'Cutoff frequency and quality should only be specified when creating a new filter by type'
          end

          f.wrap(self, in_place: in_place)

        when f.respond_to?(:process)
          MB::Sound::SampleWrapper.new(f, self, in_place: in_place)

        else
          raise "Unsupported filter type: #{filter_or_type.inspect}"
        end
      end

      # Wraps this arithmetic signal graph in a softclip effect.
      def softclip(threshold = 0.25, limit = 1.0)
        MB::Sound::Filter::SampleWrapper.new(
          MB::Sound::SoftestClip.new(threshold: threshold, limit: limit),
          self
        )
      end

      # Overridden by users of this mixin to return the inputs to the current
      # object.  For example, a Mixer will return a list of objects that are
      # added together by that mixer, as well as any constant DC offset
      # applied.
      #
      # See #graph for a method that returns every source feeding into this
      # node.
      def sources
        []
      end

      # Returns a list of all nodes feeding into this node, either directly or
      # indirectly.
      def graph
        source_history = Set.new(self)
        source_queue = sources.dup

        until source_queue.empty?
          s = source_queue.shift
          next if source_history.include?(s)

          source_history << s
          source_queue.concat(s.sources) if s.respond_to?(:sources)
        end

        source_history.to_a
      end
    end
  end
end
