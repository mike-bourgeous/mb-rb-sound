module MB
  module Sound
    # Methods related to analyzing room acoustics, such as RT60
    module AcousticsMethods
      # Calculates the RT60 (reverberation time to -60dB), or decay time to the
      # given +:level+ (as a ratio with the peak) if given, from the highest
      # amplitude peak within the +data+ (a 1D Numo::NArray or a Ruby Array of
      # 1D Numo::NArray).  If +data+ is a Ruby Array, then the RT60 is
      # calculated for each Numo::NArray within the Array.
      #
      # The decay +:level+ may be anything from -inf to 1, exclusive, and
      # defaults to -60dB (0.001).  The sample +:rate+ defaults to 48000.
      #
      # Returns the number of seconds to reach the given ratio, or raises an
      # error if that level is never reached.
      def rt60(data, level: -60.dB, rate: 48000)
        return data.map { |c| rt60(c, level: level) } if data.is_a?(Array)
        raise 'Data must be a 1D Numo::NArray' unless data.is_a?(Numo::NArray) && data.ndim == 1

        # Some other ideas:
        # - find peak, then calculate a series of RT20, do the appropriate mean
        #   (geometric?  arithmetic probably), and convert to RT60

        # Convert to instantaneous magnitude form
        # FIXME: analytic_signal drastically changes the envelope
        # FIXME: e.g. analytic_signal(Numo::SFloat.logspace(0, -4, 48000) *
        # FIXME: 123.Hz.sample(48000)) ends with analytic signal around 0.2, not
        # FIXME: 0.0001.
        asig = peak_envelope(data, monotonic: true, blend: :linear)  # XXX analytic_signal(data).abs
        peak_idx = asig.max_index
        peak_val = asig[peak_idx]
        target_val = peak_val * level

        decay_val = peak_val
        asig[peak_idx..].each_with_index do |d, idx|
          decay_val = d
          return idx.to_f / rate if decay_val <= target_val
        end

        # TODO: derive an RT60 from whatever decay we do find?
        raise ArgumentError, "Signal never reaches #{level.to_db}; minimum is #{(decay_val / peak_val).to_db}"
      end

      # Returns a list of offsets with positive and negative peaks between zero
      # crossings.
      #
      # TODO: This probably belongs in a different class/module.
      def peak_list(data)
        return data.map { |c| peak_envelope(data) } if data.is_a?(Array)
        raise 'Data must be a 1D Numo::NArray' unless data.is_a?(Numo::NArray) && data.ndim == 1

        # { index: Integer, value: Float }
        peak_list = []

        prior_val = data[0]
        prior_max_val = data[0]
        prior_max_idx = 0
        max_val = data[0]
        max_idx = 0

        # TODO: store RMS for the half-wave represented by each peak for use in RT60 energy decay calculation?

        # TODO: include zero crossings in the list too?
        # TODO: maybe create a distortion/low-pass filter that interpolates
        # between peaks, or between peaks and zeros
        data.each_with_index do |v, idx|
          if (idx == 1 && (prior_val > 0 && v < 0) || (prior_val < 0 && v > 0)) || (idx > 1 && prior_val >= 0 != v >= 0)
            # Sign changed; record the last peak
            peak_list << { index: max_idx, value: max_val }
            prior_max_val = max_val
            prior_max_idx = max_idx
            max_idx = idx
            max_val = v
          end

          if v.abs > max_val.abs
            max_idx = idx
            max_val = v
          end

          prior_val = v
        end

        if max_idx != prior_max_idx && max_val != 0
          # Record the last peak
          peak_list << { index: max_idx, value: max_val }
        end

        peak_list
      end

      # Returns the index (within the peaks array, not within the data) of the
      # largest peak by absolute value in the list of +peaks+.
      def peak_max_index(peaks)
        return 0 if peaks.nil? || peaks.empty?

        # Writing the loop directly is 1.3x-1.5x faster than
        # .each_with_index.max_by, and 2.6x-2.7x faster than .rindex(.max).
        max_idx = 0
        max_val = peaks[0][:value].abs

        peaks.each_with_index do |v, idx|
          val = v[:value].abs
          if val >= max_val
            max_val = val
            max_idx = idx
          end
        end

        max_idx
      end

      # Returns the index (within the peaks array, not within the data) of the
      # smallest peak by absolute value in the list of +peaks+.
      def peak_min_index(peaks)
        return 0 if peaks.nil? || peaks.empty?

        min_idx = 0
        min_val = peaks[0][:value].abs

        peaks.each_with_index do |v, idx|
          val = v[:value].abs
          if val < min_val
            min_val = val
            min_idx = idx
          end
        end

        min_idx
      end

      def peak_min_max_min(peaks)
        pre_min_val = post_min_val = max_val = peaks[0][:value]
        pre_min_idx = 0
        post_min_idx = 0
        max_idx = 0

        raise NotImplementedError, 'TODO'
      end

      # Like #peak_list, but with any peaks removed that are not monotonically
      # decreasing from the largest peak in either direction toward the minimum
      # on either side.
      def monotonic_peak_list(data)
        return data.map { |c| monotonic_envelope(c) } if data.is_a?(Array)

        peaks = peak_list(data)

        raise 'No peaks found' if peaks.nil? || peaks.empty?

        monotonic_peaks = []

        # TODO: Would it be possible to merge the search for these into a single iteration?  We could at least merge pre_min and max, and could maybe also get the post-peak min by resetting that min search every time we find a new max.
        max_peak = peak_max_index(peaks)
        pre_min = peak_min_index(peaks[0...max_peak])
        post_min = peak_min_index(peaks[(max_peak + 1)..-1]) + max_peak + 1

        monotonic_peaks << peaks[pre_min]

        # Rise to peak
        prior = peaks[pre_min][:value].abs
        for idx in (pre_min + 1)...max_peak do
          p = peaks[idx]
          val = p[:value].abs
          if val.abs >= prior
            monotonic_peaks << p
            prior = val
          end
        end

        monotonic_peaks << peaks[max_peak]

        # Fall from peak
        tail_peaks = []
        prior = peaks[post_min][:value].abs
        for idx in (post_min - 1).downto(max_peak + 1) do
          p = peaks[idx]
          val = p[:value].abs
          if val.abs >= prior
            tail_peaks << p
            prior = val
          end
        end

        monotonic_peaks.concat(tail_peaks.reverse)
        monotonic_peaks << peaks[post_min]

        monotonic_peaks
      end

      # Generates an envelope from the given +data+ by looking for peaks
      # between zero crossings and interpolating between them.
      def peak_envelope(data, include_negative: true, monotonic: false, blend: :catmull_rom)
        return data.map { |c| peak_envelope(data) } if data.is_a?(Array)
        raise 'Data must be a 1D Numo::NArray' unless data.is_a?(Numo::NArray) && data.ndim == 1
        raise 'Data must not be empty' if data.empty?

        # TODO: A monotonic envelope finder could operate on raw data instead
        # of the peak list, allowing finding envelopes for things that never
        # cross zero.
        peaks = monotonic ? monotonic_peak_list(data) : peak_list(data)
        peaks.select! { |p| p[:value] >= 0 } unless include_negative

        keyframes = []

        if peaks.empty? || peaks[0][:index] > 0
          # Add the first value as a keyframe if there isn't a peak there
          keyframes << { time: 0, data: [data[0].abs] }
        end

        keyframes.concat(
          peaks.map { |p|
            {
              time: p[:index],
              data: [p[:value].abs],
            }
          }
        )

        if peaks.empty? || peaks[-1][:index] < (data.length - 1) && data.length > 1
          # Add the last value as a keyframe if there isn't a peak there
          keyframes << { time: data.length - 1, data: [data[-1].abs] }
        end

        # FIXME: Catmull-Rom returns nans in the specs
        # FIXME: Catmull-Rom just looks like linear when plotted
        # data = 1000.hz.lowpass.process(noise.sample(48000) * Numo::SFloat.logspace(0, -4, 48000))
        # plot peak_envelope(data, blend: :catmull_rom, monotonic: true), graphical: true, samples: 4800000
        interp = TimelineInterpolator.new(keyframes, default_blend: blend)

        result = Numo::SFloat.new(data.length).allocate
        result.each_with_index do |v, idx|
          result[idx] = interp.value(idx)
        end

        result
      end
    end
  end
end
