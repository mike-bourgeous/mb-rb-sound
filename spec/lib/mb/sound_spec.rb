require 'fileutils'

RSpec.describe MB::Sound do
  context 'IOMethods' do
    describe '.read' do
      it 'can read a sound file' do
        a = MB::Sound.read('sounds/sine/sine_100_1s_mono.flac')
        expect(a.length).to eq(1)
        expect(a[0].length).to eq(48000)
        expect(a[0].max).to be_between(0.4, 1.0)
      end

      it 'can read part of a sound file' do
        a = MB::Sound.read('sounds/sine/sine_100_1s_mono.flac', max_frames: 500)
        expect(a.length).to eq(1)
        expect(a[0].length).to eq(500)
      end
    end

    describe '.write' do
      before(:each) do
        FileUtils.mkdir_p('tmp')
        File.unlink('tmp/sound_write_test.flac') rescue nil
        File.unlink('tmp/sound_write_exists.flac') rescue nil
      end

      context 'when writing to a file that does not yet exist' do
        let(:name) { 'tmp/sound_write_test.flac' }
        let(:data) { Numo::SFloat[0, 0.5, -0.5, 0] }

        it 'can write an array of NArrays to a sound file' do
          MB::Sound.write(name, [data], rate: 48000)
          info = MB::Sound::FFMPEGInput.parse_info(name)
          expect(info[:streams][0][:duration_ts]).to eq(4)
        end

        it 'can write a raw NArray to a sound file' do
          MB::Sound.write(name, data, rate: 48000)
          info = MB::Sound::FFMPEGInput.parse_info(name)
          expect(info[:streams][0][:duration_ts]).to eq(4)
        end

        it 'can write a Tone to a sound file' do
          MB::Sound.write(name, 100.hz.for(1), rate: 48000)
          info = MB::Sound::FFMPEGInput.parse_info(name)
          expect(info[:streams][0][:duration_ts]).to eq(48000)
          expect(info[:streams][0][:channels]).to eq(1)
        end

        it 'can write multiple tones to a sound file' do
          MB::Sound.write(name, [100.hz.for(1), 200.hz.for(1)], rate: 48000)
          info = MB::Sound::FFMPEGInput.parse_info(name)
          expect(info[:streams][0][:duration_ts]).to eq(48000)
          expect(info[:streams][0][:channels]).to eq(2)
        end
      end

      context 'when overwrite is false (by default)' do
        it 'raises an error if the sound already exists' do
          name = 'tmp/sound_write_exists.flac'
          FileUtils.touch(name)
          expect {
            MB::Sound.write(name, [Numo::SFloat[0, 0.1, -0.2, 0.3]], rate: 48000)
          }.to raise_error(MB::Sound::FileExistsError)
        end
      end

      context 'when overwrite is true' do
        it 'overwrites an existing file' do
          name = 'tmp/sound_write_exists.flac'

          FileUtils.touch(name)
          expect(File.size(name)).to eq(0)

          MB::Sound.write(name, [Numo::SFloat[0, 0.1, -0.2, 0.3]], rate: 48000, overwrite: true)
          expect(File.size(name)).to be > 0
        end
      end
    end
  end

  context 'FFTMethods' do
    [:fft, :real_fft].each do |m|
      describe m do
        it 'can process a Tone object' do
          fft = MB::Sound.send(m, 4000.hz.at(1).for(1))
          expect(fft.abs.max_index).to eq(4000)
          expect(fft[4000].abs.round(3)).to eq(1)
        end

        it 'can process an Array of Tone objects' do
          fft = MB::Sound.send(m, [4000.hz.at(1).for(1), 8000.hz.at(1).for(1)])
          expect(fft).to be_a(Array)
          expect(fft[0].abs.max_index).to eq(4000)
          expect(fft[1].abs.max_index).to eq(8000)
          expect(fft[0][4000].abs.round(3)).to eq(1)
          expect(fft[0][8000].abs.round(3)).to eq(0)
          expect(fft[1][4000].abs.round(3)).to eq(0)
          expect(fft[1][8000].abs.round(3)).to eq(1)
        end
      end
    end

    3.times do |n|
      ndim = n + 1

      context "with a #{ndim}D array" do
        let(:dc_input_small) {
          Numo::DFloat.ones(*([10] * ndim))
        }

        let(:dc_input_large) {
          Numo::DFloat.ones(*([32] * ndim))
        }

        let(:sine_input_small) {
          tone = Numo::DFloat.cast(12000.hz.at(1).generate(24))
          n.times do
            tone = Numo::DFloat.cast([tone] * 24)
          end
          tone
        }

        let(:sine_input_large) {
          tone = Numo::DFloat.cast(4000.hz.at(1).generate(48))
          n.times do
            tone = Numo::DFloat.cast([tone] * 48)
          end
          tone
        }

        let(:small_idx) {
            [0] * n + [6]
        }

        let(:large_idx) {
            [0] * n + [4]
        }

        let(:cosine_input) {
          tone = Numo::DFloat.cast(12000.hz.with_phase(90.degrees).at(1).generate(24))
          n.times do
            tone = Numo::DFloat.cast([tone] * 24)
          end
          tone
        }

        let(:ramp_input) {
          tone = Numo::DFloat.cast(4000.hz.ramp.at(1).generate(48))
          n.times do
            tone = Numo::DFloat.cast([tone] * 48)
          end
          tone
        }

        let(:all_inputs) {
          {
            dc_input_small: dc_input_small,
            dc_input_large: dc_input_large,
            sine_input_small: sine_input_small,
            sine_input_large: sine_input_large,
            cosine_input: cosine_input,
            ramp_input: ramp_input,
          }
        }

        describe '.fft' do
          it 'returns a DC value of 2.0 for an array filled with ones' do
            expect(MB::Sound.fft(dc_input_small)[*([0] * ndim)].real.round(4)).to eq(2)
            expect(MB::Sound.fft(dc_input_small)[*([1] * ndim)].real.round(4)).to eq(0)
            expect(MB::Sound.fft(dc_input_small)[*([0] * ndim)].imag.round(4)).to eq(0)
            expect(MB::Sound.fft(dc_input_small)[*([1] * ndim)].imag.round(4)).to eq(0)
            expect(MB::Sound.fft(dc_input_small).sum.real.round(5)).to eq(2)
            expect(MB::Sound.fft(dc_input_small).sum.imag.round(5)).to eq(0)

            expect(MB::Sound.fft(dc_input_large)[*([0] * ndim)].real.round(4)).to eq(2)
            expect(MB::Sound.fft(dc_input_large)[*([1] * ndim)].real.round(4)).to eq(0)
            expect(MB::Sound.fft(dc_input_large)[*([0] * ndim)].imag.round(4)).to eq(0)
            expect(MB::Sound.fft(dc_input_large)[*([1] * ndim)].imag.round(4)).to eq(0)
            expect(MB::Sound.fft(dc_input_large).sum.real.round(5)).to eq(2)
            expect(MB::Sound.fft(dc_input_large).sum.imag.round(5)).to eq(0)
          end

          it 'returns + and - bin values of +/-1i for a bin-centered sinusoid' do
            small_fft = MB::Sound.fft(sine_input_small)
            expect(small_fft.abs.sum.round(6)).to eq(2)
            expect(MB::Sound::M.round(small_fft[*small_idx], 6)).to eq(0-1i)
            expect(MB::Sound::M.round(small_fft[*small_idx.map(&:-@)], 6)).to eq(0+1i)

            large_fft = MB::Sound.fft(sine_input_large)
            expect(large_fft.abs.sum.round(6)).to eq(2)
            expect(MB::Sound::M.round(large_fft[*large_idx], 6)).to eq(0-1i)
            expect(MB::Sound::M.round(large_fft[*large_idx.map(&:-@)], 6)).to eq(0+1i)
          end

          it 'returns 0 phase for a cosine' do
            fft = MB::Sound.fft(cosine_input)
            expect(fft[*small_idx].real.round(6)).to eq(1)
            expect(fft[*small_idx].imag.round(6)).to eq(0)
            expect(fft[*small_idx.map(&:-@)].abs.round(6)).to eq(1)
            expect(fft[*small_idx.map(&:-@)].arg.round(6)).to eq(0)
          end

          it 'returns PI/4 phase for a sine' do
            fft = MB::Sound.fft(sine_input_small)
            expect(fft[*small_idx].abs.round(6)).to eq(1)
            expect(fft[*small_idx].arg.round(6)).to eq(-(Math::PI / 2).round(6))
            expect(fft[*small_idx.map(&:-@)].abs.round(6)).to eq(1)
            expect(fft[*small_idx.map(&:-@)].arg.round(6)).to eq((Math::PI / 2).round(6))
          end

          it 'can process an Array of Float' do
            small_fft = MB::Sound.fft(sine_input_small.to_a)
            expect(small_fft.abs.sum.round(6)).to eq(2)
            expect(MB::Sound::M.round(small_fft[*small_idx], 6)).to eq(0-1i)
          end

          it 'can process an Array of Complex' do
            small_fft = MB::Sound.fft(Numo::SComplex.cast(sine_input_small).to_a)
            expect(Numo::SComplex.cast(small_fft).abs.sum.round(6)).to eq(2)
            expect(MB::Sound::M.round(small_fft[*small_idx], 6)).to eq(0-1i)
          end

          it 'can process an Array of NArrays' do
            ffts = MB::Sound.fft([sine_input_small, sine_input_large])
            expect(ffts[0][*small_idx].abs.round).to eq(1)
            expect(ffts[1][*large_idx].abs.round).to eq(1)
          end
        end

        describe '.ifft' do
          it "returns the original signal when passed the output of #fft" do
            all_inputs.each do |name, input|
              fft = MB::Sound.fft(input)
              inv_fft = MB::Sound.ifft(fft).real

              # Including the name so the diff for failed comparisons will show the name
              expect([name, MB::Sound::M.round(inv_fft, 6)]).to eq([name, MB::Sound::M.round(input, 6)])
            end
          end

          it 'returns an array of all ones for a 2.0 DC value' do
            dc_fft = Numo::DFloat.zeros([5] * ndim)
            dc_fft[0] = 2
            result = MB::Sound.ifft(dc_fft)
            expect(result.sum.abs.round(6)).to eq(5 ** ndim)
            expect(result.abs.min.round(6)).to eq(1)
            expect(result.abs.max.round(6)).to eq(1)
          end

          it 'can process an Array of Complex' do
            fft_arr = MB::Sound.fft(sine_input_small).to_a

            first = fft_arr
            while first.is_a?(Array)
              first = first[0]
            end
            expect(first).to be_a(Complex)

            inv_fft = MB::Sound.ifft(fft_arr)
            expect(MB::Sound::M.round(inv_fft, 6)).to eq(MB::Sound::M.round(sine_input_small, 6))
          end

          it 'can process an Array of NArrays' do
            ffts = MB::Sound.fft(all_inputs.values)
            inv_ffts = MB::Sound.ifft(ffts)
            expect(MB::Sound::M.round(inv_ffts, 6)).to eq(MB::Sound::M.round(all_inputs.values, 6))
          end
        end

        describe '.real_fft' do
          it 'returns only the positive frequencies' do
            expect(MB::Sound.real_fft(ramp_input).shape).to eq([48] * (ndim - 1) + [25])
          end

          it 'returns a DC value of 2.0 for an array filled with ones' do
            expect(MB::Sound.real_fft(dc_input_small)[*([0] * ndim)].real.round(4)).to eq(2)
            expect(MB::Sound.real_fft(dc_input_small)[*([1] * ndim)].real.round(4)).to eq(0)
            expect(MB::Sound.real_fft(dc_input_small)[*([0] * ndim)].imag.round(4)).to eq(0)
            expect(MB::Sound.real_fft(dc_input_small)[*([1] * ndim)].imag.round(4)).to eq(0)
            expect(MB::Sound.real_fft(dc_input_small).sum.real.round(5)).to eq(2)
            expect(MB::Sound.real_fft(dc_input_small).sum.imag.round(5)).to eq(0)

            expect(MB::Sound.real_fft(dc_input_large)[*([0] * ndim)].real.round(4)).to eq(2)
            expect(MB::Sound.real_fft(dc_input_large)[*([1] * ndim)].real.round(4)).to eq(0)
            expect(MB::Sound.real_fft(dc_input_large)[*([0] * ndim)].imag.round(4)).to eq(0)
            expect(MB::Sound.real_fft(dc_input_large)[*([1] * ndim)].imag.round(4)).to eq(0)
            expect(MB::Sound.real_fft(dc_input_large).sum.real.round(5)).to eq(2)
            expect(MB::Sound.real_fft(dc_input_large).sum.imag.round(5)).to eq(0)
          end

          it 'returns a bin value of -1i for a bin-centered sinusoid' do
            small_fft = MB::Sound.real_fft(sine_input_small)
            expect(MB::Sound::M.round(small_fft[*small_idx], 6)).to eq(0-1i)
            expect(small_fft.abs.sum.round(6)).to eq(1)

            large_fft = MB::Sound.real_fft(sine_input_large)
            expect(MB::Sound::M.round(large_fft[*large_idx], 6)).to eq(0-1i)
            expect(large_fft.abs.sum.round(6)).to eq(1)
          end

          it 'returns 0 phase for a cosine' do
            fft = MB::Sound.real_fft(cosine_input)
            expect(fft[*small_idx].real.round(6)).to eq(1)
            expect(fft[*small_idx].imag.round(6)).to eq(0)
          end

          it 'returns PI/4 phase for a sine' do
            fft = MB::Sound.real_fft(sine_input_small)
            expect(fft[*small_idx].abs.round(6)).to eq(1)
            expect(fft[*small_idx].arg.round(6)).to eq(-(Math::PI / 2).round(6))
          end

          it 'can process an Array of Float' do
            small_fft = MB::Sound.real_fft(sine_input_small.to_a)
            expect(small_fft.abs.sum.round(6)).to eq(1)
            expect(MB::Sound::M.round(small_fft[*small_idx], 6)).to eq(0-1i)
          end

          it 'can process an Array of NArrays' do
            ffts = MB::Sound.real_fft([sine_input_small, sine_input_large])
            expect(ffts[0][*small_idx].abs.round).to eq(1)
            expect(ffts[1][*large_idx].abs.round).to eq(1)
          end
        end

        describe '.real_ifft' do
          it "returns the original signal when passed the output of #real_fft" do
            all_inputs.each do |name, input|
              fft = MB::Sound.real_fft(input)
              inv_fft = MB::Sound.real_ifft(fft)

              # Including the name so the diff for failed comparisons will show the name
              expect([name, MB::Sound::M.round(inv_fft, 6)]).to eq([name, MB::Sound::M.round(input, 6)])
            end
          end

          it 'returns an array of all ones for a 2.0 DC value' do
            dc_fft = Numo::DFloat.zeros([5] * ndim)
            dc_fft[0] = 2
            result = MB::Sound.real_ifft(dc_fft)
            expect(result.sum.abs.round(6)).to eq(result.length)
            expect(result.abs.min.round(6)).to eq(1)
            expect(result.abs.max.round(6)).to eq(1)
          end

          it 'can process an Array of Complex' do
            fft_arr = MB::Sound.real_fft(sine_input_small).to_a

            first = fft_arr
            while first.is_a?(Array)
              first = first[0]
            end
            expect(first).to be_a(Complex)

            inv_fft = MB::Sound.real_ifft(fft_arr)
            expect(MB::Sound::M.round(inv_fft, 6)).to eq(MB::Sound::M.round(sine_input_small, 6))
          end

          it 'can process an Array of NArrays' do
            ffts = MB::Sound.real_fft(all_inputs.values)
            inv_ffts = MB::Sound.real_ifft(ffts)
            expect(MB::Sound::M.round(inv_ffts, 6)).to eq(MB::Sound::M.round(all_inputs.values, 6))
          end

          context 'with odd_length: true' do
            if ndim == 1
              it "returns the original data from an odd-length dataset with #{ndim} dimensions" do
                all_inputs.each do |name, input|
                  odd = input[0..-2]
                  fft = MB::Sound.real_fft(odd)
                  inv_fft = MB::Sound.real_ifft(fft, odd_length: true)

                  expect([name, MB::Sound::M.round(inv_fft, 6)]).to eq([name, MB::Sound::M.round(odd, 6)])
                end
              end

              it 'can process a numeric Array' do
                odd = sine_input_small[0..-2].to_a
                fft_arr = MB::Sound.real_fft(odd)
                inv_fft = MB::Sound.real_ifft(fft_arr, odd_length: true)
                expect(MB::Sound::M.round(inv_fft, 6)).to eq(MB::Sound::M.round(odd, 6))
              end
            else
              pending "#{ndim} dimensions"
            end
          end
        end
      end
    end
  end

  describe '.filter' do
    it 'reduces the amplitude of high frequencies more than low frequencies' do
      low = MB::Sound.filter(123.hz.at(0.1), frequency: 1000, quality: 0.5)
      low_gain = low[0].abs.max / 0.1

      high = MB::Sound.filter(15000.hz.at(0.1), frequency: 1000, quality: 0.5)
      high_gain = high[0].abs.max / 0.1

      expect(low_gain).to be > high_gain
      expect(low_gain).to be > -1.db
      expect(high_gain).to be < -30.db
    end
  end
end
