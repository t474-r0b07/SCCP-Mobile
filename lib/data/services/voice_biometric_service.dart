import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class VoiceBiometricExtractResult {
  final bool ok;
  final List<double>? embedding;
  final double quality;
  final String message;

  const VoiceBiometricExtractResult({
    required this.ok,
    required this.embedding,
    required this.quality,
    required this.message,
  });
}

class VoiceBiometricVerifyResult {
  final bool ok;
  final double score;
  final double quality;
  final String message;

  const VoiceBiometricVerifyResult({
    required this.ok,
    required this.score,
    required this.quality,
    required this.message,
  });
}

class VoiceBiometricService {
  VoiceBiometricService._();

  static const double defaultAcceptThreshold = 0.86;

  static Future<VoiceBiometricExtractResult> extractEmbeddingFromWavFile(
    String wavPath,
  ) async {
    try {
      final file = File(wavPath);
      if (!await file.exists()) {
        return const VoiceBiometricExtractResult(
          ok: false,
          embedding: null,
          quality: 0,
          message: 'Archivo de voz no encontrado',
        );
      }

      final bytes = await file.readAsBytes();
      final pcm = _decodeWavPcm16Mono(bytes);
      if (pcm == null) {
        return const VoiceBiometricExtractResult(
          ok: false,
          embedding: null,
          quality: 0,
          message: 'Formato de audio no compatible (WAV PCM16 requerido)',
        );
      }

      final extracted = _extractEmbedding(
        samples: pcm.samples,
        sampleRate: pcm.sampleRate,
      );
      return extracted;
    } catch (_) {
      return const VoiceBiometricExtractResult(
        ok: false,
        embedding: null,
        quality: 0,
        message: 'No se pudo procesar la muestra de voz',
      );
    }
  }

  static Future<VoiceBiometricVerifyResult> verifyWavAgainstProfile({
    required String wavPath,
    required List<double> profileEmbedding,
    double acceptThreshold = defaultAcceptThreshold,
  }) async {
    if (profileEmbedding.isEmpty) {
      return const VoiceBiometricVerifyResult(
        ok: false,
        score: 0,
        quality: 0,
        message: 'Perfil biometrico ausente',
      );
    }

    final extracted = await extractEmbeddingFromWavFile(wavPath);
    if (!extracted.ok || extracted.embedding == null) {
      return VoiceBiometricVerifyResult(
        ok: false,
        score: 0,
        quality: extracted.quality,
        message: extracted.message,
      );
    }

    final score = cosineSimilarity(extracted.embedding!, profileEmbedding);
    final passed = extracted.quality >= 0.45 && score >= acceptThreshold;
    return VoiceBiometricVerifyResult(
      ok: passed,
      score: score,
      quality: extracted.quality,
      message: passed
          ? 'Huella de voz validada'
          : 'Huella de voz no coincide con el perfil',
    );
  }

  static List<double>? averageEmbeddings(List<List<double>> embeddings) {
    final valid = embeddings.where((e) => e.isNotEmpty).toList();
    if (valid.isEmpty) return null;
    final dims = valid.first.length;
    if (dims == 0) return null;
    final accum = List<double>.filled(dims, 0);
    var count = 0;
    for (final emb in valid) {
      if (emb.length != dims) continue;
      for (var i = 0; i < dims; i++) {
        accum[i] += emb[i];
      }
      count += 1;
    }
    if (count == 0) return null;
    final avg = List<double>.generate(dims, (i) => accum[i] / count);
    return _normalizeL2(avg);
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0;
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na <= 0 || nb <= 0) return 0;
    final denom = math.sqrt(na) * math.sqrt(nb);
    if (denom == 0) return 0;
    return (dot / denom).clamp(-1.0, 1.0);
  }

  static VoiceBiometricExtractResult _extractEmbedding({
    required List<double> samples,
    required int sampleRate,
  }) {
    if (samples.length < sampleRate) {
      return const VoiceBiometricExtractResult(
        ok: false,
        embedding: null,
        quality: 0,
        message: 'Muestra demasiado corta',
      );
    }

    final centered = _removeDc(samples);
    final frameSize = math.max((sampleRate * 0.02).round(), 160);
    final frames = _chunk(centered, frameSize);
    if (frames.isEmpty) {
      return const VoiceBiometricExtractResult(
        ok: false,
        embedding: null,
        quality: 0,
        message: 'Audio invalido',
      );
    }

    final frameRms = frames.map(_rms).toList();
    final noiseFloor = _percentile(frameRms, 0.2);
    final threshold = math.max(0.015, noiseFloor * 2.2);

    final voicedFrames = <List<double>>[];
    final noiseFrames = <List<double>>[];
    for (var i = 0; i < frames.length; i++) {
      if (frameRms[i] >= threshold) {
        voicedFrames.add(frames[i]);
      } else {
        noiseFrames.add(frames[i]);
      }
    }
    final voiced = voicedFrames.expand((e) => e).toList();
    if (voiced.length < (sampleRate * 1.2)) {
      return const VoiceBiometricExtractResult(
        ok: false,
        embedding: null,
        quality: 0.1,
        message: 'Habla insuficiente, repite en voz clara',
      );
    }

    final voiceRatio = voiced.length / centered.length;
    final voicedRms = _rms(voiced);
    final noiseRms = noiseFrames.isEmpty
        ? noiseFloor
        : _mean(noiseFrames.map(_rms).toList());
    final snrDb = 20 *
        _safeLog10(((voicedRms + 1e-9) / ((noiseRms <= 0 ? 1e-9 : noiseRms))));
    final quality = ((voiceRatio * 0.55) +
            (((snrDb + 8) / 30).clamp(0.0, 1.0) * 0.45))
        .clamp(0.0, 1.0);

    final zcr = _zeroCrossingRate(voiced);
    final absMean = _mean(voiced.map((v) => v.abs()).toList());
    final totalRms = _rms(voiced);
    final peak = voiced.fold<double>(0, (p, v) => math.max(p, v.abs()));
    final p95 = _percentile(voiced.map((v) => v.abs()).toList(), 0.95);
    final p50 = _percentile(voiced.map((v) => v.abs()).toList(), 0.50);
    final dynRange = (p95 - p50).clamp(0.0, 1.0);

    final voicedFrameRms = voicedFrames.map(_rms).toList();
    final frameMean = _mean(voicedFrameRms);
    final frameStd = _stddev(voicedFrameRms, frameMean);
    final frameCv = frameMean <= 0 ? 0.0 : (frameStd / frameMean);

    final pitchHz = _estimatePitchHz(
      voiced,
      sampleRate,
      minHz: 85,
      maxHz: 340,
    );

    final spectral = _spectralFeatures(voiced, sampleRate);

    final raw = <double>[
      absMean,
      totalRms,
      zcr,
      peak,
      dynRange,
      frameMean,
      frameStd,
      frameCv,
      (pitchHz / 350).clamp(0.0, 1.2),
      (snrDb / 25).clamp(-1.0, 1.5),
      spectral.centroidNorm,
      spectral.rolloffNorm,
      spectral.lowBandRatio,
      spectral.midBandRatio,
      spectral.highBandRatio,
      spectral.bandwidthNorm,
      voiceRatio,
    ];

    final embedding = _normalizeL2(raw);
    return VoiceBiometricExtractResult(
      ok: true,
      embedding: embedding,
      quality: quality,
      message: 'Huella extraida',
    );
  }

  static _SpectralFeatures _spectralFeatures(
    List<double> samples,
    int sampleRate,
  ) {
    final n = math.min(1024, samples.length);
    if (n < 256) {
      return const _SpectralFeatures(
        centroidNorm: 0,
        rolloffNorm: 0,
        lowBandRatio: 0,
        midBandRatio: 0,
        highBandRatio: 0,
        bandwidthNorm: 0,
      );
    }

    final windowed = List<double>.generate(n, (i) {
      final w = 0.54 - 0.46 * math.cos((2 * math.pi * i) / (n - 1));
      return samples[i] * w;
    });

    final maxBin = n ~/ 2;
    final mags = List<double>.filled(maxBin + 1, 0);
    for (var k = 0; k <= maxBin; k++) {
      var re = 0.0;
      var im = 0.0;
      for (var t = 0; t < n; t++) {
        final angle = (2 * math.pi * k * t) / n;
        re += windowed[t] * math.cos(angle);
        im -= windowed[t] * math.sin(angle);
      }
      mags[k] = math.sqrt((re * re) + (im * im));
    }

    var total = 0.0;
    var weightedFreq = 0.0;
    var weightedSq = 0.0;
    var low = 0.0;
    var mid = 0.0;
    var high = 0.0;
    final nyquist = sampleRate / 2.0;
    final binHz = nyquist / maxBin;

    for (var k = 1; k <= maxBin; k++) {
      final m = mags[k];
      final f = k * binHz;
      total += m;
      weightedFreq += (m * f);
      weightedSq += (m * f * f);
      if (f < 400) {
        low += m;
      } else if (f < 1400) {
        mid += m;
      } else if (f < 3500) {
        high += m;
      }
    }

    if (total <= 0) {
      return const _SpectralFeatures(
        centroidNorm: 0,
        rolloffNorm: 0,
        lowBandRatio: 0,
        midBandRatio: 0,
        highBandRatio: 0,
        bandwidthNorm: 0,
      );
    }

    final centroid = weightedFreq / total;
    final variance = (weightedSq / total) - (centroid * centroid);
    final bandwidth = variance <= 0 ? 0.0 : math.sqrt(variance);

    final target = total * 0.85;
    var cumulative = 0.0;
    double rolloff = 0.0;
    for (var k = 1; k <= maxBin; k++) {
      cumulative += mags[k];
      if (cumulative >= target) {
        rolloff = k * binHz;
        break;
      }
    }

    return _SpectralFeatures(
      centroidNorm: (centroid / nyquist).clamp(0.0, 1.0),
      rolloffNorm: (rolloff / nyquist).clamp(0.0, 1.0),
      lowBandRatio: (low / total).clamp(0.0, 1.0),
      midBandRatio: (mid / total).clamp(0.0, 1.0),
      highBandRatio: (high / total).clamp(0.0, 1.0),
      bandwidthNorm: (bandwidth / nyquist).clamp(0.0, 1.0),
    );
  }

  static double _estimatePitchHz(
    List<double> voiced,
    int sampleRate, {
    required int minHz,
    required int maxHz,
  }) {
    final windowSize = math.min(sampleRate, voiced.length);
    if (windowSize < 400) return 0;
    final s = voiced.sublist(0, windowSize);
    final minLag = (sampleRate / maxHz).floor();
    final maxLag = (sampleRate / minHz).ceil();
    if (maxLag <= minLag || maxLag >= s.length) return 0;

    var bestLag = 0;
    var bestCorr = -1.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      var num = 0.0;
      var den1 = 0.0;
      var den2 = 0.0;
      final limit = s.length - lag;
      for (var i = 0; i < limit; i++) {
        final a = s[i];
        final b = s[i + lag];
        num += a * b;
        den1 += a * a;
        den2 += b * b;
      }
      final den = math.sqrt(den1 * den2);
      if (den <= 0) continue;
      final corr = num / den;
      if (corr > bestCorr) {
        bestCorr = corr;
        bestLag = lag;
      }
    }
    if (bestLag <= 0 || bestCorr < 0.25) return 0;
    return sampleRate / bestLag;
  }

  static List<List<double>> _chunk(List<double> source, int frameSize) {
    if (frameSize <= 0) return const [];
    final out = <List<double>>[];
    for (var i = 0; i + frameSize <= source.length; i += frameSize) {
      out.add(source.sublist(i, i + frameSize));
    }
    return out;
  }

  static List<double> _removeDc(List<double> x) {
    if (x.isEmpty) return const [];
    final mean = _mean(x);
    return x.map((v) => v - mean).toList();
  }

  static double _rms(List<double> x) {
    if (x.isEmpty) return 0;
    var sum = 0.0;
    for (final v in x) {
      sum += v * v;
    }
    return math.sqrt(sum / x.length);
  }

  static double _zeroCrossingRate(List<double> x) {
    if (x.length < 2) return 0;
    var count = 0;
    for (var i = 1; i < x.length; i++) {
      if ((x[i - 1] >= 0 && x[i] < 0) || (x[i - 1] < 0 && x[i] >= 0)) {
        count++;
      }
    }
    return count / (x.length - 1);
  }

  static double _mean(List<double> x) {
    if (x.isEmpty) return 0;
    var sum = 0.0;
    for (final v in x) {
      sum += v;
    }
    return sum / x.length;
  }

  static double _stddev(List<double> x, double mean) {
    if (x.length < 2) return 0;
    var sum = 0.0;
    for (final v in x) {
      final d = v - mean;
      sum += d * d;
    }
    return math.sqrt(sum / (x.length - 1));
  }

  static double _percentile(List<double> x, double p) {
    if (x.isEmpty) return 0;
    final sorted = [...x]..sort();
    final idx = (p.clamp(0, 1) * (sorted.length - 1)).round();
    return sorted[idx];
  }

  static double _safeLog10(double v) {
    final safe = v <= 1e-12 ? 1e-12 : v;
    return math.log(safe) / math.ln10;
  }

  static List<double> _normalizeL2(List<double> v) {
    if (v.isEmpty) return const [];
    var norm = 0.0;
    for (final value in v) {
      norm += value * value;
    }
    if (norm <= 0) return List<double>.filled(v.length, 0);
    final scale = 1 / math.sqrt(norm);
    return v.map((value) => value * scale).toList();
  }

  static _WavPcmData? _decodeWavPcm16Mono(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final bd = ByteData.sublistView(bytes);

    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') return null;

    int? sampleRate;
    int channels = 1;
    int bitsPerSample = 16;
    int? dataOffset;
    int? dataSize;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = bd.getUint32(offset + 4, Endian.little);
      final chunkDataOffset = offset + 8;
      if (chunkDataOffset + size > bytes.length) break;

      if (id == 'fmt ' && size >= 16) {
        final audioFormat = bd.getUint16(chunkDataOffset, Endian.little);
        channels = bd.getUint16(chunkDataOffset + 2, Endian.little);
        sampleRate = bd.getUint32(chunkDataOffset + 4, Endian.little);
        bitsPerSample = bd.getUint16(chunkDataOffset + 14, Endian.little);
        if (audioFormat != 1) return null;
      } else if (id == 'data') {
        dataOffset = chunkDataOffset;
        dataSize = size;
      }

      offset = chunkDataOffset + size + (size.isOdd ? 1 : 0);
    }

    if (sampleRate == null ||
        dataOffset == null ||
        dataSize == null ||
        bitsPerSample != 16 ||
        channels <= 0) {
      return null;
    }

    final bytesPerSample = bitsPerSample ~/ 8;
    final frameBytes = bytesPerSample * channels;
    if (frameBytes <= 0) return null;
    final totalFrames = dataSize ~/ frameBytes;
    if (totalFrames <= 0) return null;

    final samples = List<double>.filled(totalFrames, 0);
    var read = dataOffset;
    for (var i = 0; i < totalFrames; i++) {
      final v = bd.getInt16(read, Endian.little);
      samples[i] = (v / 32768.0).clamp(-1.0, 1.0);
      read += frameBytes;
    }

    return _WavPcmData(sampleRate: sampleRate, samples: samples);
  }
}

class _WavPcmData {
  final int sampleRate;
  final List<double> samples;

  const _WavPcmData({
    required this.sampleRate,
    required this.samples,
  });
}

class _SpectralFeatures {
  final double centroidNorm;
  final double rolloffNorm;
  final double lowBandRatio;
  final double midBandRatio;
  final double highBandRatio;
  final double bandwidthNorm;

  const _SpectralFeatures({
    required this.centroidNorm,
    required this.rolloffNorm,
    required this.lowBandRatio,
    required this.midBandRatio,
    required this.highBandRatio,
    required this.bandwidthNorm,
  });
}
