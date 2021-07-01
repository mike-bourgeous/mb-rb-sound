RSpec.describe(MB::Sound::PlotMethods) do
  before(:each) do
    ENV['PLOT_TERMINAL'] = 'dumb'
    ENV['PLOT_WIDTH'] = '80'
    ENV['PLOT_HEIGHT'] = '40'
    MB::Sound.close_plotter
    MB::Sound.plotter(width: 80, height: 40).print = false
  end

  after(:each) do
    ENV.delete('PLOT_TERMINAL')
    ENV.delete('PLOT_WIDTH')
    ENV.delete('PLOT_HEIGHT')
    MB::Sound.close_plotter
  end

  let(:tone) { 357.2.hz.gauss }

  # Makes sure the regex matches a full line and isn't accidentally matching a
  # zero-width string and isn't matching across lines
  def check_regex(text, regex)
    expect(text).to match(regex)
    expect(text.match(regex).to_s).not_to include("\n")
    expect(text.match(regex).to_s.length).to be_between(75, 81).inclusive
  end

  describe '#hist' do
    it 'can draw a histogram' do
      lines = MB::Sound.hist(tone).map(&MB::U.method(:remove_ansi))
      expect(lines.length).to be_between(37, 41).inclusive
      
      text = lines.join("\n")
      check_regex(text, /^\s*1000 \|-\+\s+\* {5,10}\*.*\|$/)
      check_regex(text, /^\s*200 \|-\+\s+\* {15,25}\*.*\|$/)
    end
  end

  describe '#mag_phase' do
    it 'includes both magnitude and phase graphs' do
      lines = MB::Sound.mag_phase(440.hz.sine).map(&MB::U.method(:remove_ansi))
      expect(lines.length).to be_between(37, 41).inclusive

      text = lines.join("\n")
      expect(text).to include('mag **')
      expect(text).to include('phase **')
    end
  end

  describe '#time_freq' do
    it 'includes both time and frequency graphs' do
      lines = MB::Sound.time_freq(tone).map(&MB::U.method(:remove_ansi))
      expect(lines.length).to be_between(37, 41).inclusive

      text = lines.join("\n")
      expect(text).to include('time **')
      expect(text).to include('freq **')
      expect(text).not_to match(/^\s*0 .*\*{5,}.*\|$/) # no extended dwell at zero
      check_regex(text, /^\s*0 .*(\*+[^*|]+){12,}.*\|$/) # at least 12 zero crossings
      check_regex(text, /^\s*-40 .*\*{10,}.*\|$/) # lots of frequency plot density
    end
  end

  describe '#spectrum' do
    it 'can plot a spectrogram of a sine wave' do
      expect(MB::Sound).to receive(:puts).with(/Plotting/)
      lines = MB::Sound.spectrum(400.hz.sine, samples: 1200).map(&MB::U.method(:remove_ansi))
      expect(lines.length).to be_between(37, 41).inclusive

      text = lines.join("\n")
      expect(text).to include('0 ***')

      r1 = /^.*-70 [^*]+(\*+[^*|]+){2}[^*|]+\|$/
      check_regex(text, r1)

      r2 = /^.*-30 [^*]+(\*+[^*|]+){1,2}[^*|]+\|$/
      check_regex(text, r2)
    end

    it 'can plot a spectrogram of a more complex wave' do
      expect(MB::Sound).to receive(:puts).with(/Plotting/)
      lines = MB::Sound.spectrum(480.hz.gauss, samples: 800).map(&MB::U.method(:remove_ansi))
      expect(lines.length).to be_between(37, 41).inclusive

      text = lines.join("\n")
      expect(text).to include('0 ***')
      check_regex(text, /^.*-40 [^*]+(\*+[^*|]+){7,9}[^*|]+\|$/)
      check_regex(text, /^.*-30 [^*]+(\*+[^*|]+){1,3}[^*|]+\|$/)

      expect(text.match(/^.*-30 [^*]+(\*+[^*|]+){1,3}[^*|]+\|$/).to_s.length).to be_between(75, 81).inclusive
    end
  end

  describe '#plot' do
    it 'can plot a Tone' do
      expect(MB::Sound).to receive(:puts).with(/Plotting.*Tone/m)
      lines = MB::Sound.plot(tone)
      expect(lines.length).to be_between(37, 41).inclusive
    end

    it 'can plot a sound file' do
      expect(MB::Sound).to receive(:puts).with(/Plotting.*synth0.flac/m)
      lines = MB::Sound.plot('sounds/synth0.flac')
      expect(lines.length).to be_between(37, 41).inclusive
      expect(lines.select { |l| l.include?('------------') }.length).to eq(4)

      text = MB::U.remove_ansi(lines.join("\n"))
      expect(text).to include('0 **')
      expect(text).to include('1 **')
      expect(text).not_to include('2 **')
    end

    it 'can plot a Numo::NArray' do
      expect(MB::Sound).to receive(:puts).with(/Plotting.*Numo/m)
      lines = MB::Sound.plot(tone.generate(800))
      expect(lines.length).to be_between(37, 41).inclusive

      text = MB::U.remove_ansi(lines.join("\n"))
      expect(text).to include('0 **')
      expect(text).not_to include('1 **')
      check_regex(text, /^\s*0 .*(\*+[^*|]+){3,5}.*\|$/) # 4 zero crossings
    end

    it 'can plot an array of different sounds' do
      expect(MB::Sound).to receive(:puts).with(/Plotting.*[^\e]\[/m)
      lines = MB::Sound.plot([123.hz.sine, 123.hz.ramp, 123.hz.triangle, 123.hz.gauss])
      expect(lines.length).to be_between(37, 41).inclusive

      expect(lines.select { |l| l.match(/-{12,}.* {6,}.*-{12,}/) }.length).to eq(4)

      text = MB::U.remove_ansi(lines.join("\n"))
      expect(text).to include('0 **')
      expect(text).to include('1 **')
      expect(text).to include('2 **')
      expect(text).to include('3 **')
    end
  end
end
