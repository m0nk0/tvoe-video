package com.tvoymagazine.tvoe_video

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Добавляет аудиодорожку к немому MP4.
 * MP3/любой формат → PCM 16 bit → обработка (громкость, задержка, фейд, обрезка) → AAC → Mux.
 * Все методы вызывать из одного worker-потока.
 */
object AudioMuxer {

    private const val AAC_BITRATE = 192_000
    private const val FADE_MS = 1000

        fun mux(
        videoPath: String,
        audioPath: String,
        outputPath: String,
        volume: Double,
        startSec: Double,
        durationMs: Int
    ): String {
        val dir = File(outputPath).parentFile ?: File(videoPath).parentFile!!
        val stamp = System.currentTimeMillis()
        val pcmFile = File(dir, "tmp_audio_$stamp.pcm")
        val aacFile = File(dir, "tmp_audio_$stamp.m4a")

        try {
            val info = decodeAndProcess(
                audioPath, pcmFile, volume, startSec, durationMs
            )
            if (!pcmFile.exists() || pcmFile.length() == 0L) {
                throw RuntimeException("Не удалось подготовить PCM")
            }
            encodeAac(pcmFile, aacFile, info.sampleRate, info.channels)
            if (!aacFile.exists() || aacFile.length() == 0L) {
                throw RuntimeException("Не удалось закодировать AAC")
            }
            // ✅ ИСПРАВЛЕНО: aacFile.path вместо aacFile (combine ждёт String)
            combine(videoPath, aacFile.path, outputPath)
            return outputPath
        } finally {
            try { pcmFile.delete() } catch (_: Throwable) {}
            try { aacFile.delete() } catch (_: Throwable) {}
        }
    }

    private class PcmInfo(val sampleRate: Int, val channels: Int)

    // ==========================================
    // ПРОХОД 1: декодирование + обработка → raw PCM
    // ==========================================
    private fun decodeAndProcess(
        audioPath: String,
        pcmFile: File,
        volume: Double,
        startSec: Double,
        durationMs: Int
    ): PcmInfo {
        if (durationMs <= 0) throw IllegalArgumentException("Нулевая длительность видео")

        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        val out = BufferedOutputStream(FileOutputStream(pcmFile), 1 shl 16)

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
                throw RuntimeException("В файле нет аудиодорожки: $audioPath")
            }
            extractor.selectTrack(trackIndex)

            val mime = srcFormat.getString(MediaFormat.KEY_MIME)!!
            val dec = MediaCodec.createDecoderByType(mime)
            decoder = dec

            // Просим 16-битный PCM (API 24+). Если декодер не умеет — конфигурируем без ключа.
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

            var decoderFormat: MediaFormat? = null
            var rate = 0
            var srcChannels = 0
            var outChannels = 0
            var totalFrames = 0L
            var fadeFrames = 0L
            var fadeStartFrame = 0L
            var writtenFrames = 0L
            var initialized = false
            val gain = volume.coerceIn(0.0, 1.0)
            val silence = ByteArray(16 * 1024)

            fun writeSilence(frames: Long) {
                var bytesLeft = frames * outChannels * 2
                while (bytesLeft > 0) {
                    val n = minOf(bytesLeft, silence.size.toLong()).toInt()
                    out.write(silence, 0, n)
                    bytesLeft -= n
                }
            }

            fun ensureInit(): Boolean {
                if (initialized) return true
                val f = decoderFormat ?: srcFormat ?: return false
                if (!f.containsKey(MediaFormat.KEY_SAMPLE_RATE) ||
                    !f.containsKey(MediaFormat.KEY_CHANNEL_COUNT)
                ) return false

                rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                srcChannels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                if (rate <= 0 || srcChannels <= 0) {
                    throw RuntimeException("Некорректный формат аудио: rate=$rate ch=$srcChannels")
                }
                outChannels = if (srcChannels > 2) 2 else srcChannels

                totalFrames = (durationMs / 1000.0 * rate).toLong()
                if (totalFrames <= 0) throw RuntimeException("Слишком короткая длительность")

                fadeFrames = (FADE_MS / 1000.0 * rate).toLong()
                fadeStartFrame = (totalFrames - fadeFrames).coerceAtLeast(0L)

                val delayFrames = (startSec.coerceAtLeast(0.0) * rate).toLong()
                    .coerceIn(0L, totalFrames)
                writeSilence(delayFrames)
                writtenFrames = delayFrames

                initialized = true
                return true
            }

            ensureInit()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var guard = 0

            while (!outputDone && writtenFrames < totalFrames) {
                if (++guard > 2_000_000) throw RuntimeException("Зацикливание декодера")

                if (!inputDone) {
                    val inIdx = dec.dequeueInputBuffer(10_000L)
                    if (inIdx >= 0) {
                        val buf = dec.getInputBuffer(inIdx)!!
                        buf.clear()
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            dec.queueInputBuffer(
                                inIdx, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM
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
                    decoderFormat = dec.outputFormat
                    val enc = if (decoderFormat!!.containsKey(MediaFormat.KEY_PCM_ENCODING))
                        decoderFormat!!.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    else AudioFormat.ENCODING_PCM_16BIT
                    if (enc != AudioFormat.ENCODING_PCM_16BIT) {
                        throw RuntimeException("Декодер выдал не 16-битный PCM (encoding=$enc)")
                    }
                    ensureInit()
                } else if (outIdx >= 0) {
                    if (info.size > 0) {
                        if (!ensureInit()) {
                            dec.releaseOutputBuffer(outIdx, false)
                            continue
                        }
                        val buf = dec.getOutputBuffer(outIdx)!!
                        val bytes = ByteArray(info.size)
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        buf.get(bytes)

                        val srcStride = srcChannels * 2
                        val frames = info.size / srcStride
                        val src = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                        val dst = ByteBuffer.allocate(frames * outChannels * 2)
                            .order(ByteOrder.LITTLE_ENDIAN)

                        var f = 0
                        while (f < frames && writtenFrames < totalFrames) {
                            var g = gain
                            if (fadeFrames > 0 && writtenFrames >= fadeStartFrame) {
                                val t = (writtenFrames - fadeStartFrame).toDouble() / fadeFrames
                                g *= (1.0 - t).coerceIn(0.0, 1.0)
                            }
                            for (c in 0 until outChannels) {
                                val s = src.getShort((f * srcChannels + c) * 2).toInt()
                                var v = Math.round(s * g).toInt()
                                if (v > 32767) v = 32767
                                if (v < -32768) v = -32768
                                dst.putShort(v.toShort())
                            }
                            writtenFrames++
                            f++
                        }
                        out.write(dst.array(), 0, dst.position())
                    }
                    dec.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }

            if (!initialized) throw RuntimeException("Не удалось определить формат аудио")

            // Добиваем тишиной, если трек короче видео
            if (writtenFrames < totalFrames) {
                writeSilence(totalFrames - writtenFrames)
            }

            out.flush()
            return PcmInfo(rate, outChannels)
        } finally {
            try { out.close() } catch (_: Throwable) {}
            try { decoder?.stop() } catch (_: Throwable) {}
            try { decoder?.release() } catch (_: Throwable) {}
            try { extractor.release() } catch (_: Throwable) {}
        }
    }

    // ==========================================
    // ПРОХОД 2: raw PCM → AAC (.m4a)
    // ==========================================
    private fun encodeAac(pcmFile: File, aacFile: File, sampleRate: Int, channels: Int) {
        val mime = MediaFormat.MIMETYPE_AUDIO_AAC
        val format = MediaFormat.createAudioFormat(mime, sampleRate, channels)
        format.setInteger(
            MediaFormat.KEY_AAC_PROFILE,
            MediaCodecInfo.CodecProfileLevel.AACObjectLC
        )
        format.setInteger(MediaFormat.KEY_BIT_RATE, AAC_BITRATE)
        format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 64 * 1024)

        val encoder = MediaCodec.createEncoderByType(mime)
        var muxer: MediaMuxer? = null
        val input = BufferedInputStream(FileInputStream(pcmFile), 1 shl 16)

        var trackIndex = -1
        var muxerStarted = false
        var samplesWritten = 0

        try {
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            muxer = MediaMuxer(aacFile.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val bytesPerFrame = channels * 2
            val chunk = ByteArray(16 * 1024)
            val info = MediaCodec.BufferInfo()
            var ptsUs = 0L
            var inputDone = false
            var outputDone = false
            var guard = 0

            while (!outputDone) {
                if (++guard > 2_000_000) throw RuntimeException("Зацикливание AAC-энкодера")

                if (!inputDone) {
                    val inIdx = encoder.dequeueInputBuffer(10_000L)
                    if (inIdx >= 0) {
                        val buf = encoder.getInputBuffer(inIdx)!!
                        buf.clear()
                        val cap = minOf(buf.capacity(), chunk.size)
                        val toRead = (cap / bytesPerFrame) * bytesPerFrame
                        val n = if (toRead > 0) input.read(chunk, 0, toRead) else -1
                        if (n <= 0) {
                            encoder.queueInputBuffer(
                                inIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            buf.put(chunk, 0, n)
                            encoder.queueInputBuffer(inIdx, 0, n, ptsUs, 0)
                            ptsUs += (n / bytesPerFrame) * 1_000_000L / sampleRate
                        }
                    }
                }

                val outIdx = encoder.dequeueOutputBuffer(info, 10_000L)
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    if (muxerStarted) throw RuntimeException("Формат AAC изменился дважды")
                    trackIndex = muxer.addTrack(encoder.outputFormat)
                    muxer.start()
                    muxerStarted = true
                } else if (outIdx >= 0) {
                    val buf = encoder.getOutputBuffer(outIdx)!!
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                        info.size = 0
                    }
                    if (info.size > 0 && muxerStarted) {
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        muxer.writeSampleData(trackIndex, buf, info)
                        samplesWritten++
                    }
                    encoder.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }

            if (!muxerStarted || samplesWritten == 0) {
                throw RuntimeException("AAC-энкодер не выдал данных")
            }
            muxer.stop()
        } finally {
            try { input.close() } catch (_: Throwable) {}
            try { encoder.stop() } catch (_: Throwable) {}
            try { encoder.release() } catch (_: Throwable) {}
            try { muxer?.release() } catch (_: Throwable) {}
        }
    }

    // ==========================================
    // ПРОХОД 3: видео + AAC → финальный MP4 (с интерливингом)
    // ==========================================
    private fun combine(videoPath: String, audioPath: String, outputPath: String) {
        val vEx = MediaExtractor()
        val aEx = MediaExtractor()
        var muxer: MediaMuxer? = null

        try {
            vEx.setDataSource(videoPath)
            var vTrack = -1
            var vFmt: MediaFormat? = null
            for (i in 0 until vEx.trackCount) {
                val f = vEx.getTrackFormat(i)
                val m = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (m.startsWith("video/")) { vTrack = i; vFmt = f; break }
            }
            if (vTrack < 0 || vFmt == null) {
                throw RuntimeException("В немом файле нет видеодорожки")
            }
            vEx.selectTrack(vTrack)

            aEx.setDataSource(audioPath)
            var aTrack = -1
            var aFmt: MediaFormat? = null
            for (i in 0 until aEx.trackCount) {
                val f = aEx.getTrackFormat(i)
                val m = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (m.startsWith("audio/")) { aTrack = i; aFmt = f; break }
            }
            if (aTrack < 0 || aFmt == null) {
                throw RuntimeException("Во временном AAC нет аудиодорожки")
            }
            aEx.selectTrack(aTrack)

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val outV = muxer.addTrack(vFmt)
            val outA = muxer.addTrack(aFmt)
            muxer.start()

            fun bufSize(f: MediaFormat): Int {
                val declared = if (f.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE))
                    f.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) else 0
                return maxOf(declared, 512 * 1024)
            }

            val vBuf = ByteBuffer.allocate(bufSize(vFmt))
            val aBuf = ByteBuffer.allocate(bufSize(aFmt))
            val vInfo = MediaCodec.BufferInfo()
            val aInfo = MediaCodec.BufferInfo()
            var vHas = false
            var aHas = false
            var vEos = false
            var aEos = false
            var guard = 0

            while (true) {
                if (++guard > 5_000_000) throw RuntimeException("Зацикливание муксера")

                if (!vHas && !vEos) {
                    vBuf.clear()
                    val s = vEx.readSampleData(vBuf, 0)
                    if (s < 0) {
                        vEos = true
                    } else {
                        vInfo.set(0, s, vEx.sampleTime, vEx.sampleFlags)
                        vHas = true
                        vEx.advance()
                    }
                }
                if (!aHas && !aEos) {
                    aBuf.clear()
                    val s = aEx.readSampleData(aBuf, 0)
                    if (s < 0) {
                        aEos = true
                    } else {
                        aInfo.set(0, s, aEx.sampleTime, aEx.sampleFlags)
                        aHas = true
                        aEx.advance()
                    }
                }

                if (!vHas && !aHas) break

                val writeVideo = when {
                    !vHas -> false
                    !aHas -> true
                    else -> vInfo.presentationTimeUs <= aInfo.presentationTimeUs
                }

                if (writeVideo) {
                    vBuf.position(0)
                    vBuf.limit(vInfo.size)
                    muxer.writeSampleData(outV, vBuf, vInfo)
                    vHas = false
                } else {
                    aBuf.position(0)
                    aBuf.limit(aInfo.size)
                    muxer.writeSampleData(outA, aBuf, aInfo)
                    aHas = false
                }
            }

            muxer.stop()
        } finally {
            try { vEx.release() } catch (_: Throwable) {}
            try { aEx.release() } catch (_: Throwable) {}
            try { muxer?.release() } catch (_: Throwable) {}
        }
    }
}