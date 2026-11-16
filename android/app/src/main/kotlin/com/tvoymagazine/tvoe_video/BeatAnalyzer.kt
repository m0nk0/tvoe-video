package com.tvoymagazine.tvoe_video

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Анализ битов в аудиофайле.
 * Возвращает: beats (секунды), bpm, waveform (нормализованный 0..1), durationSec.
 */
object BeatAnalyzer {

    private const val RMS_WINDOW_MS = 50L      // окно RMS: 50 мс
    private const val MIN_BEAT_INTERVAL = 0.25 // минимальный интервал между битами (сек)
    private const val SENSITIVITY = 1.4        // порог пика над локальной средней
    private const val PEAK_WINDOW = 20         // окно локальной средней (в обе стороны)
    private const val MIN_BEATS = 4            // минимум битов для валидного BPM
    private const val BPM_LOW = 40.0
    private const val BPM_HIGH = 220.0
    private const val WAVEFORM_POINTS_PER_SEC = 20.0

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
                srcFormat.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
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

            fun ensureInit(): Boolean {
                if (initialized) return true
                val f = outFormat ?: srcFormat ?: return false
                if (!f.containsKey(MediaFormat.KEY_SAMPLE_RATE) ||
                    !f.containsKey(MediaFormat.KEY_CHANNEL_COUNT)
                ) return false
                sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                if (sampleRate <= 0 || channels <= 0) {
                    throw RuntimeException("Некорректный формат: rate=$sampleRate ch=$channels")
                }
                initialized = true
                return true
            }

            // Собираем RMS по окнам RMS_WINDOW_MS миллисекунд
            val rmsValues = mutableListOf<Double>()
            val rmsTimesMs = mutableListOf<Long>() // время в ms от начала

            val samplesPerWindow = (sampleRate.toDouble() * RMS_WINDOW_MS / 1000.0).toInt()
                .coerceAtLeast(1)
            var windowSamples = 0L
            var windowSumSq = 0.0
            var currentWindowMs = 0L
            var totalSamplesProcessed = 0L

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
                    totalSamplesProcessed++

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
                if (++guard > 5_000_000) throw RuntimeException("Зацикливание анализатора")

                if (!inputDone) {
                    val inIdx = dec.dequeueInputBuffer(10_000L)
                    if (inIdx >= 0) {
                        val buf = dec.getInputBuffer(inIdx)!!
                        buf.clear()
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            dec.queueInputBuffer(inIdx, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
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

            // Добить последнее неполное окно
            if (windowSamples > 0) flushWindow()

            if (rmsValues.size < 8) {
                return Result(emptyList(), 0.0, emptyList(), durationSec)
            }

            // === Waveform: сжимаем в ~WAVEFORM_POINTS_PER_SEC точек на секунду ===
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

            // === Поиск пиков ===
            val beats = mutableListOf<Double>()
            var lastBeat = -1.0
            for (i in PEAK_WINDOW until rmsValues.size - PEAK_WINDOW) {
                val from = (i - PEAK_WINDOW).coerceAtLeast(0)
                val to = (i + PEAK_WINDOW).coerceAtMost(rmsValues.size - 1)
                var sum = 0.0
                for (j in from..to) sum += rmsValues[j]
                val avg = sum / (to - from + 1)

                val isPeak = rmsValues[i] > avg * SENSITIVITY &&
                        rmsValues[i] > rmsValues[i - 1] &&
                        rmsValues[i] >= rmsValues[i + 1]

                val tSec = rmsTimesMs[i] / 1000.0
                if (isPeak && (lastBeat < 0 || tSec - lastBeat >= MIN_BEAT_INTERVAL)) {
                    beats.add(tSec)
                    lastBeat = tSec
                }
            }

            if (beats.size < MIN_BEATS) {
                return Result(emptyList(), 0.0, waveform, durationSec)
            }

            // === BPM по медиане интервалов ===
            val intervals = mutableListOf<Double>()
            for (i in 1 until beats.size) {
                intervals.add(beats[i] - beats[i - 1])
            }
            intervals.sort()
            val median = intervals[intervals.size / 2]
            val bpm = if (median > 0) 60.0 / median else 0.0

            return Result(beats, bpm, waveform, durationSec)
        } finally {
            try { decoder?.stop() } catch (_: Throwable) {}
            try { decoder?.release() } catch (_: Throwable) {}
            try { extractor.release() } catch (_: Throwable) {}
        }
    }
}