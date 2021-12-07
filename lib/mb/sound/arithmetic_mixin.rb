module MB
  module Sound
    # Adds methods to any class that implements a :sample method to build
    # signal generation and processing graphs.  In combination with Tone, Note,
    # and the helper methods in MB::Sound, this creates a DSL that can quickly
    # generate complex sounds.
    #
    # Examples (run in the bin/sound.rb environment):
    #     # FM organ bass
    #     play F1.at(-6.db).fm(F2.at(300) * adsr(0, 0.1, 0.0, 0.5, auto_release: false)) * adsr(0, 0, 1, 0, auto_release: 0.25)
    #
    #     # FM 90s synth bass
    #     # See https://musictech.com/tutorials/learn-advanced-fm-synthesis-with-dexed/
    #     # FIXME: doesn't sound right at all; might need exponential FM and exponential envelopes
    #     cenv = adsr(0, 0.05, 0.01, 2.5)
    #     cenv2 = adsr(0, 0.05, 0.01, 2.5)
    #     c = cenv * C3.at(1).fm(cenv2 * C3.at(1800)).forever; nil
    #     denv = adsr(0, 0.03, 0, 5, auto_release: 1)
    #     d = denv * Tone.new(frequency: C3.frequency.constant * 0.9996 - 0.22).at(1).forever; nil
    #     eenv = adsr(0, 0.03, 0.0, 2)
    #     e = C2.at(1).fm(c * 310 + d * 300).forever; nil
    #     fenv = adsr(0, 2, 0, 2)
    #     f = C2.fm(e * 300) * fenv; nil
    #     play f
    module ArithmeticMixin
      # Creates a mixer that adds this mixer's output to +other+.  Part of a
      # DSL experiment for building up a signal graph.
      def +(other)
        fixup_tones(false, self, other)
        Mixer.new([self, other])
      end

      # Creates a mixer that subtracts +other+ from this mixer's output.  Part
      # of a DSL experiment for building up a signal graph.
      def -(other)
        fixup_tones(false, self, other)
        Mixer.new([self, [other, -1]])
      end

      # Creates a multiplier that multiplies +other+ by this mixer's output.
      # Part of a DSL experiment for building up a signal graph.
      def *(other)
        fixup_tones(false, self)
        fixup_tones(true, other)
        Multiplier.new([self, other])
      end

      # Divides incoming data by +other+, which may be a Numeric or another
      # signal graph.
      def /(other)
        if other.respond_to?(:sample)
          self.proc { |v|
            v.inplace!
            v / other.sample(v.length)
            v.not_inplace!
          }
        else
          self.proc { |v|
            v.inplace!
            v / other
            v.not_inplace!
          }
        end
      end

      # Appends a node that raises the incoming values to +other+, which should
      # be either a numeric or another signal graph.
      def **(other)
        if other.respond_to?(:sample)
          self.proc { |v|
            data = other.sample(v.length)
            if v.nil? || data.nil?
              nil
            else
              v.inplace!
              v ** data
              v.not_inplace!
            end
          }
        else
          self.proc { |v|
            if v.nil?
              nil
            else
              v.inplace!
              v ** other
              v.not_inplace!
            end
          }
        end
      end

      # Appends a node that calculates the natural logarithm of values passing
      # through.
      def log
        self.proc { |v| MB::FastSound.narray_log(v) }
      end

      # Appends a node that calculates the base two logarithm of values passing
      # through.
      def log2
        self.proc { |v| MB::FastSound.narray_log2(v) }
      end

      # Appends a node that calculates the base two logarithm of values passing
      # through.
      def log10
        self.proc { |v| MB::FastSound.narray_log10(v) }
      end

      # Wraps the numeric in a MB::Sound::Constant so that numeric values can
      # be listed first in signal graph arithmetic operations.
      def coerce(numeric)
        [numeric.constant, self]
      end

      # Adds a Ruby block to a processing chain.  The block will be called with
      # a Numo::NArray containing samples to be modified.  Note that this can
      # be very slow compared to the built-in algorithms implemented in C.
      def proc(&block)
        class << block
          include ArithmeticMixin

          def sample(count)
            data = @orig.sample(count)
            return nil if data.nil?
            call(data)
          end

          def sources
            [@orig]
          end
        end

        # TODO: is there a better way to pass a closure or otherwise pass a
        # value into a singleton class or singleton method?  It feels like I've
        # done this before somewhere but can't recall.
        block.instance_variable_set(:@orig, self)

        block
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

      private

      # Sets tones to play forever at full volume, if they don't have a fixed
      # volume and duration set.
      def fixup_tones(fix_amp, *tones)
        tones.each do |t|
          t.or_for(nil) if t.respond_to?(:or_for) # Default to playing forever
          t.or_at(1) if fix_amp && t.respond_to?(:or_at) # Default to full volume
        end
      end
    end
  end
end
