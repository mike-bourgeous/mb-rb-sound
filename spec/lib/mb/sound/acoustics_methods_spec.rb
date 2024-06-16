RSpec.describe(MB::Sound::AcousticsMethods, aggregate_failures: true) do
  describe '#rt60' do
    it 'defaults to -60dB and a sample rate of 48kHz' do
      data = Numo::SFloat.logspace(0, -4, 48000)
      expect(MB::Sound.rt60(data)).to be_within(0.05).of(0.75)
    end
  end

  describe '#peak_list' do
    it 'can return a list of peaks for a trivial input' do
      data = Numo::SFloat[0, 1, 0, -1, 0]
      expect(MB::Sound.peak_list(data)).to eq([{ index: 1, value: 1 }, { index: 3, value: -1 }])
    end

    it 'can return peaks in a slightly more varied input' do
      data = Numo::SFloat[0, -1, -1.125, -0.9, 0, 1.5, 1, 0]
      expect(MB::Sound.peak_list(data)).to eq([{ index: 2, value: -1.125 }, { index: 5, value: 1.5 }])
    end

    it 'returns a peak that occurs after the last zero crossing' do
      data = Numo::SFloat[0, 1, 0, -1, 0, 0.5, 1, 0.25]
      expect(MB::Sound.peak_list(data)).to eq([
        { index: 1, value: 1 },
        { index: 3, value: -1 },
        { index: 6, value: 1 },
      ])
    end

    it 'returns a peak that occurs at the very end' do
      data = Numo::SFloat[0, 1, 0, -1, 0, 0.5, 1]
      expect(MB::Sound.peak_list(data)).to eq([
        { index: 1, value: 1 },
        { index: 3, value: -1 },
        { index: 6, value: 1 },
      ])
    end

    it 'can identify peaks without zeroes bewteen' do
      data = Numo::SFloat[1, -1, 0.5, -0.5]
      expect(MB::Sound.peak_list(data)).to eq([
        { index: 0, value: 1 },
        { index: 1, value: -1 },
        { index: 2, value: 0.5 },
        { index: 3, value: -0.5 },
      ])
    end

    it 'does not count a leading zero as a peak if the first peak is negative' do
      data = Numo::SFloat[0, -1, 0, 1, 0]
      expect(MB::Sound.peak_list(data)).to eq([{ index: 1, value: -1 }, { index: 3, value: 1 }])
    end

    it 'returns a single positive peak if all values are positive' do
      data = Numo::SFloat[1, 2, 3, 2, 1]
      expect(MB::Sound.peak_list(data)).to eq([{ index: 2, value: 3 }])
    end

    it 'returns a single negative peak if all values are negative' do
      data = Numo::SFloat[-1, -2, -2.5, -3, -1]
      expect(MB::Sound.peak_list(data)).to eq([{ index: 3, value: -3 }])
    end
  end
end
