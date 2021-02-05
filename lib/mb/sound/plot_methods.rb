module MB
  module Sound
    # Command-line interface methods related to plotting sounds.  MB::Sound
    # extends itself with this module.
    module PlotMethods
      # Sets up SIGWINCH (window-size change) handler when MB::Sound extends
      # itself with this module.
      def self.extended(within)
        # Make sure that plotters are resized when the terminal window changes
        # size.
        old_handler = trap :WINCH do
          Thread.new do
            within.reset_plotter
          end

          old_handler.call if old_handler.respond_to?(:call)
        end
      end

      # Called by the SIGWINCH signal handler to resize plots when the terminal
      # window is resized.
      def reset_plotter
        old_pt = @pt
        old_pg = @pg
        @pt&.close
        @pg&.close
        @pt = nil
        @pg = nil

        plotter(graphical: false) if old_pt
        plotter(graphical: true) if old_pg
      end

      # Returns either a terminal-based plotting object if +graphical+ is false,
      # or a graphical window-based plotting object if +graphical+ is true.
      #
      # Overriding this method to return some other compatible object allows
      # other plotting systems to be used by the CLI DSL.
      def plotter(graphical: false)
        @pt ||= MB::Sound::Plot.terminal(height_fraction: 0.8)
        @pg ||= MB::Sound::Plot.new if graphical
        graphical ? @pg : @pt
      end

      # Plots the spectrum of the given data (split into chunks).  This method
      # is for convenience and just calls #plot(..., spectrum: true).
      def spectrum(data, **kwargs)
        plot(data, **kwargs, spectrum: true)
      end

      # Plots time-domain and frequency-domain magnitudes of the given data.
      # Supports plotting filter responses.
      def time_freq(data, **kwargs)
        data = any_sound_to_array(data)

        plot(
          data.flat_map { |c|
            if c.is_a?(Filter)
              [c.impulse_response, c.frequency_response.abs.map { |v| v.to_db }]
            else
              [c, real_fft(c).abs.map { |v| v.to_db }]
            end
          },
          **kwargs
        )
      end

      # Plots frequency-domain magnitude and phase of the given data.  Supports
      # plotting filter responses.
      def mag_phase(data, **kwargs)
        data = any_sound_to_array(data)

        freq = data.map { |c| c.is_a?(Filter) ? c.frequency_response(2000) : real_fft(c) }

        mag = freq.map.with_index { |c, idx|
          [
            "#{idx} mag",
            {
              data: c.abs.map { |v| v.to_db }.clip(-80, 80),
              logscale: true,
            }
          ]
        }

        mag_min = mag.map { |v| v[1][:data].min }.min
        mag_max = mag.map { |v| v[1][:data].max }.max
        mag_range = [mag_min, mag_max]
        mag.each do |v|
          v[1][:yrange] = mag_range
        end

        phase = freq.map.with_index { |c, idx|
          [
            "#{idx} phase",
            {
              data: c.arg,
              yrange: [-Math::PI, Math::PI],
              logscale: true,
            }
          ]
        }

        plotinfo = mag.zip(phase).flat_map { |v| v }.to_h

        plotter(graphical: kwargs[:graphical] || false).plot(plotinfo)
      end

      # Plots a subset of the given audio file, test tone, or data, starting at
      # +offset+, and plotting the following +samples+ samples.  If +all+ is true
      # then the entirety of the file, tone, or data will be plotted in slices of
      # +samples+ samples.
      def plot(file_tone_data, samples: 960, offset: 0, all: false, graphical: false, spectrum: false)
        # FIXME: This function is hard to read
        STDOUT.write("\e[H\e[2J") if all == true

        if all == true || all == false
          header = "\e[36mPlotting #{MB::Sound::U.highlight(file_tone_data)}\e[0m"
          header_lines = header.lines.count
          puts header
        end

        case file_tone_data
        when Array, Numo::NArray
          data = any_sound_to_array(file_tone_data)

        when String
          # TODO: Read speaker names
          data = read(file_tone_data, max_frames: all ? nil : samples + offset)

        when Tone
          data = [file_tone_data.generate(all ? nil : samples + offset)]

        when Filter
          data = [file_tone_data.impulse_response, file_tone_data.frequency_response.abs]

        else
          raise "Cannot plot type #{file_tone_data.class.name}"
        end

        p = plotter(graphical: graphical)

        if all == true
          t = clock_now

          until offset >= data[0].length
            STDOUT.write("\e[#{header_lines}H\e[36mPress Ctrl-C to stop  \e[1;35m#{offset} / #{data[0].length}\e[0m\e[K\n")

            if spectrum
              p.yrange(-80, 0) if p.respond_to?(:yrange)
            else
              p.yrange(data.map(&:min).min, data.map(&:max).max) if p.respond_to?(:yrange)
            end

            plot(data, samples: samples, offset: offset, all: nil, graphical: graphical, spectrum: spectrum)

            now = clock_now
            elapsed = [now - t, 0.1].min
            t = now

            offset += elapsed * 48000

            STDOUT.flush
            sleep 0.02
          end
        else
          data = data.map { |c| c[offset...([offset + samples, c.length].min)] || [] }

          if spectrum
            p.logscale if p.respond_to?(:logscale)
            data = data.map { |c| MB::Sound.real_fft(c).abs.map(&:to_db).clip(-80, 80) }
          else
            p.logscale(false) if p.respond_to?(:logscale)
          end

          p.yrange(data.map(&:min).min, data.map(&:max).max) if p.respond_to?(:yrange) && !all.nil?

          @lines = p.plot(data.map.with_index { |c, idx| [idx.to_s, c] }.to_h, print: false)
          puts @lines
        end

        nil
      ensure
        if all == true
          if graphical
            @pg.close
            @pg = nil
          elsif @pt.respond_to?(:height)
            puts "\e[#{@pt.height + (header_lines || 2) + 2}H"
          end
        end
      end
    end
  end
end
