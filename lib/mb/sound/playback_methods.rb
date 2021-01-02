module MB
  module Sound
    # Command-line interface methods for playing sounds.  MB::Sound extends
    # itself with this module.
    module PlaybackMethods
      # Plays a sound file if a String is given, a generated tone if a Tone is
      # given, or an audio buffer if an audio buffer is given.  If an audio
      # buffer or tone is given, the sample rate should be specified (defaults to
      # 48k).  The sample rate is ignored for an audio filename.
      def play(file_tone_data, rate: 48000, gain: 1.0, plot: nil, graphical: false, device: nil)
        header = MB::Sound::U.wrap("\e[H\e[J\e[36mPlaying\e[0m #{MB::Sound::U.highlight(file_tone_data)}".lines.map(&:strip).join(' ') + "\n\n")
        puts header

        plot = { header_lines: header.lines.count, graphical: graphical } if plot.nil? || plot == true

        case file_tone_data
        when String
          return play_file(file_tone_data, gain: gain, plot: plot, device: device)

        when Array, Numo::NArray
          data = any_sound_to_array(file_tone_data)
          data = data * 2 if data.length < 2
          channels = data.length

          # TODO: if this code needs to be modified much in the future, come up
          # with a shared way of chunking data that can work for all play and
          # plot methods
          output = MB::Sound.output(rate: rate, channels: channels, plot: plot, device: device)
          buffer_size = output.buffer_size
          (0...data[0].length).step(buffer_size).each do |offset|
            output.write(data.map { |c| c[offset...([offset + buffer_size, c.length].min)] })
          end

        when Tone
          output = MB::Sound.output(rate: rate, plot: plot, device: device)
          file_tone_data.write(output)

        else
          raise "Unsupported type #{file_tone_data.class.name} for playback"
        end
      ensure
        output&.close
      end

      # Plays the given filename using the default audio output returned by
      # MB::Sound.output.  The +:channels+ parameter may be used to force mono
      # playback (mono sound is converted to stereo by default), or to ask ffmpeg
      # to upmix or downmix audio to a different number of channels.
      def play_file(filename, channels: nil, gain: 1.0, plot: true, device: nil)
        input = MB::Sound::FFMPEGInput.new(filename, channels: channels, resample: 48000)
        output = MB::Sound.output(channels: channels || (input.channels < 2 ? 2 : input.channels), plot: plot, device: device)

        buffer_size = output.buffer_size

        # TODO: Move all playback loops to a processing helper method when those are added
        loop do
          data = input.read(buffer_size)
          break if data.nil? || data.empty? || data[0].empty?

          data.map { |d|
            d.inplace * gain
          }

          # Ensure the output is at least stereo (Pulseaudio plays nothing for
          # mono output on my system)
          data = data * 2 if data.length == 1 && channels.nil?

          output.write(data)
        end

      ensure
        input&.close
        output&.close
      end

    end
  end
end
