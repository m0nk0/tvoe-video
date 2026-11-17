package com.tvoymagazine.tvoe_video

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

/**
 * Анализ битов в аудиофайле (нативный, без FFmpeg).
 * MediaExtractor -> PCM 16 bit -> RMS по окнам 50 мс -> сглаживание ->
 * адаптивный поиск пиков (3 прохода) + BPM по медиане + waveform.
 *
 * Все методы вызывать из worker-потока.
 */
object BeatAnalyzer {

    private const val RMS_WINDOW_MS = 50L       // окно RMS: 50 мс
    private const val MIN_BEAT_INTERVAL = 0.30  // мин. интервал между битами (сек)
    private const val PEAK_WINDOW = 20          // окно локальной средней (в обе стороны)
    private const val MIN_BEATS = 4             // минимум битов для валидного BPM
    private const val BPM_LOW = 40.0
    private const val BPM_HIGH = 220.0
    private const val WAVEFORM_POINTS_PER_SEC = 20.0
    private const val MAX_BEATS = 300           // защита от частокола маркеров

    // ✅ Пороги адаптивных проходов: строгий -> средний -> мягкий
    private val SENSITIVITY_PASSES = doubleArrayOf(1.5, 1.3, 1.12)

    data class Result(
        val beats: List<Double>,
        val bpm: Double,
        val waveform: List<Double>,
        val durationSec: Double
    ) {
        fun isValid(): Boolean =
            beats.size >= MIN_BEATS && bpm > BPM_LOW && bpm < BPM_HIGH
    }

    fun analyze(audioPath: String): Result {
        val file = File(audioPath)
        if (!file.exists()) throw RuntimeException("Аудиофайл не найден: $audioPath")

        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null

        try {
            extractor.setDataSource(audioPath)

            var trackIndex = -1
            var srcFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIndex = i
                    srcFormat = f
                    break
                }
            }
            if (trackIndex < 0 || srcFormat == null) {
                throw RuntimeException("В файле нет аудиодорожки")
            }

            val durationUs = if (srcFormat.containsKey(MediaFormat.KEY_DURATION))
                srcFormat.getLong(MediaFormat.KEY_DURATION) else 0L
            val durationSec = durationUs / 1_000_000.0

            extractor.selectTrack(trackIndex)

            val mime = srcFormat.getString(MediaFormat.KEY_MIME)!!
            val dec = MediaCodec.createDecoderByType(mime)
            decoder = dec

            var configured = false
            try {
                srcFormat.setInteger(
                    MediaFormat.KEY_PCM_ENCODING,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                dec.configure(srcFormat, null, null, 0)
                configured = true
            } catch (_: Throwable) {
                try { srcFormat.removeKey(MediaFormat.KEY_PCM_ENCODING) } catch (_: Throwable) {}
            }
            if (!configured) {
                dec.configure(srcFormat, null, null, 0)
            }
            dec.start()

            var outFormat: MediaFormat? = null
            var sampleRate = 0
            var channels = 0
            var initialized = false

            // ✅ Окно в семплах; пересчитывается ВНУТРИ ensureInit
            var samplesPerWindow = 0

            fun ensureInit(): Boolean {
                if (initialized) return true
                val f = outFormat ?: srcFormat ?: return false
                if (!f.containsKey(MediaFormat.KEY_SAMPLE_RATE) ||
                    !f.containsKey(MediaFormat.KEY_CHANNEL_COUNT)
                ) return false

                sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                if (sampleRate <= 0 || channels <= 0) {
                    throw RuntimeException(
                        "Некорректный формат аудио: rate=$sampleRate ch=$channels"
                    )
                }
                samplesPerWindow =
                    (sampleRate.toDouble() * RMS_WINDOW_MS / 1000.0).toInt()
                        .coerceAtLeast(1)
                initialized = true
                return true
            }

            // ==========================================
            // Накопители RMS
            // ==========================================
            val rmsValues = mutableListOf<Double>()
            val rmsTimesMs = mutableListOf<Long>()

            var windowSamples = 0L
            var windowSumSq = 0.0
            var currentWindowMs = 0L

            fun flushWindow() {
                if (windowSamples > 0) {
                    val rms = sqrt(windowSumSq / windowSamples)
                    rmsValues.add(rms)
                    rmsTimesMs.add(currentWindowMs)
                    currentWindowMs += RMS_WINDOW_MS
                }
                windowSumSq = 0.0
                windowSamples = 0L
            }

            fun processPcm(bytes: ByteArray) {
                if (!initialized) return
                val stride = channels * 2
                val frames = bytes.size / stride
                val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

                for (f in 0 until frames) {
                    var sum = 0.0
                    for (c in 0 until channels) {
                        val s = bb.getShort((f * channels + c) * 2).toInt() / 32768.0
                        sum += s * s
                    }
                    val mono = sum / channels
                    windowSumSq += mono
                    windowSamples++

                    if (windowSamples >= samplesPerWindow) {
                        flushWindow()
                    }
                }
            }

            ensureInit()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var guard = 0

            while (!outputDone) {
                if (++guard > 5_000_000) {
                    throw RuntimeException("Зацикливание анализатора битов")
                }

                if (!inputDone) {
                    val inIdx = dec.dequeueInputBuffer(10_000L)
                    if (inIdx >= 0) {
                        val buf = dec.getInputBuffer(inIdx)!!
                        buf.clear()
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            dec.queueInputBuffer(
                                inIdx, 0, 0, 0L,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            dec.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIdx = dec.dequeueOutputBuffer(info, 10_000L)
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    outFormat = dec.outputFormat
                    val enc = if (outFormat!!.containsKey(MediaFormat.KEY_PCM_ENCODING))
                        outFormat!!.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    else AudioFormat.ENCODING_PCM_16BIT
                    if (enc != AudioFormat.ENCODING_PCM_16BIT) {
                        throw RuntimeException(
                            "Декодер выдал не 16-битный PCM (encoding=$enc)"
                        )
                    }
                    ensureInit()
                } else if (outIdx >= 0) {
                    if (info.size > 0 && ensureInit()) {
                        val buf = dec.getOutputBuffer(outIdx)!!
                        val bytes = ByteArray(info.size)
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        buf.get(bytes)
                        processPcm(bytes)
                    }
                    dec.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }

            if (windowSamples > 0) flushWindow()

            if (rmsValues.size < 8) {
                return Result(emptyList(), 0.0, emptyList(), durationSec)
            }

            // ==========================================
            // Сглаживание RMS (окно 3)
            // ==========================================
            if (rmsValues.size >= 3) {
                val smoothed = DoubleArray(rmsValues.size)
                for (i in rmsValues.indices) {
                    val a = rmsValues[maxOf(0, i - 1)]
                    val b = rmsValues[i]
                    val c = rmsValues[minOf(rmsValues.size - 1, i + 1)]
                    smoothed[i] = (a + b + c) / 3.0
                }
                for (i in rmsValues.indices) rmsValues[i] = smoothed[i]
            }

            // ==========================================
            // Waveform: ~20 точек/сек, нормализация 0..1
            // ==========================================
            val totalMs = rmsTimesMs.last().toDouble()
            val waveform = if (totalMs <= 0) {
                emptyList()
            } else {
                val totalSec = totalMs / 1000.0
                val buckets = (totalSec * WAVEFORM_POINTS_PER_SEC).toInt()
                    .coerceIn(16, 4000)
                val w = MutableList(buckets) { 0.0 }
                val bucketMs = totalMs / buckets
                for (i in rmsValues.indices) {
                    val b = (rmsTimesMs[i] / bucketMs).toInt()
                        .coerceIn(0, buckets - 1)
                    if (rmsValues[i] > w[b]) w[b] = rmsValues[i]
                }
                val maxAmp = w.max()
                if (maxAmp > 0) {
                    for (i in w.indices) {
                        w[i] = (w[i] / maxAmp).coerceIn(0.0, 1.0)
                    }
                }
                w
            }

            // ==========================================
            // ✅ АДАПТИВНЫЙ ПОИСК ПИКОВ: 3 прохода
            // ==========================================
            val maxRms = rmsValues.max()
            val noiseFloor = maxRms * 0.02 // не ловим "биты" в тишине

            fun detect(sensitivity: Double): List<Double> {
                val found = mutableListOf<Double>()
                var lastBeat = -1.0
                for (i in PEAK_WINDOW until rmsValues.size - PEAK_WINDOW) {
                    val from = (i - PEAK_WINDOW).coerceAtLeast(0)
                    val to = (i + PEAK_WINDOW).coerceAtMost(rmsValues.size - 1)
                    var sum = 0.0
                    for (j in from..to) sum += rmsValues[j]
                    val avg = sum / (to - from + 1)

                    val v = rmsValues[i]
                    val isPeak = v > avg * sensitivity &&
                            v > rmsValues[i - 1] &&
                            v >= rmsValues[i + 1] &&
                            v > noiseFloor

                    val tSec = rmsTimesMs[i] / 1000.0
                    if (isPeak && (lastBeat < 0 || tSec - lastBeat >= MIN_BEAT_INTERVAL)) {
                        found.add(tSec)
                        lastBeat = tSec
                    }
                }
                return found
            }

            var beats: List<Double> = emptyList()
            for (pass in SENSITIVITY_PASSES) {
                beats = detect(pass)
                if (beats.size >= 8) break // ✅ достаточно — дальше не смягчаем
            }

            if (beats.size < MIN_BEATS) {
                return Result(emptyList(), 0.0, waveform, durationSec)
            }

            // Защита от частокола
            val finalBeats = if (beats.size > MAX_BEATS) {
                val step = Math.ceil(beats.size / MAX_BEATS.toDouble()).toInt()
                beats.filterIndexed { idx, _ -> idx % step == 0 }
            } else {
                beats
            }

            // ==========================================
            // BPM по медиане интервалов
            // ==========================================
            val intervals = mutableListOf<Double>()
            for (i in 1 until finalBeats.size) {
                intervals.add(finalBeats[i] - finalBeats[i - 1])
            }
            val bpm = if (intervals.isEmpty()) {
                0.0
            } else {
                intervals.sort()
                val median = intervals[intervals.size / 2]
                if (median > 0) 60.0 / median else 0.0
            }

            return Result(finalBeats, bpm, waveform, durationSec)
        } finally {
            try { decoder?.stop() } catch (_: Throwable) {}
            try { decoder?.release() } catch (_: Throwable) {}
            try { extractor.release() } catch (_: Throwable) {}
        }
    }
}