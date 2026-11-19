package com.tvoymagazine.tvoe_video

import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.tvoymagazine.tvoe_video/exporter"
    }

    private var workerThread: HandlerThread? = null
    private var worker: Handler? = null
    private val main = Handler(Looper.getMainLooper())
    private var encoder: VideoEncoder? = null
    private var gif: GifEncoder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (workerThread == null) {
            val t = HandlerThread("TvoeVideoEncoder")
            t.start()
            workerThread = t
            worker = Handler(t.looper)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val w = worker
                if (w == null) {
                    result.error("NO_WORKER", "Поток энкодера не готов", null)
                    return@setMethodCallHandler
                }

                when (call.method) {

                    "start" -> {
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        val fps = call.argument<Int>("fps") ?: 30
                        val bitrate = call.argument<Int>("bitrate") ?: 6_000_000
                        val path = call.argument<String>("path")
                        if (width <= 0 || height <= 0 || path.isNullOrEmpty()) {
                            result.error("BAD_ARGS", "Неверные параметры start", null)
                            return@setMethodCallHandler
                        }
                        w.post {
                            try {
                                abortOnWorker()
                                val enc = VideoEncoder(width, height, fps, bitrate, path)
                                enc.start()
                                encoder = enc
                                ok(result, true)
                            } catch (e: Throwable) { abortOnWorker(); fail(result, e) }
                        }
                    }

                    "feedFrame" -> {
                        val bytes = call.arguments as? ByteArray
                        if (bytes == null) { result.error("BAD_ARGS", "Ожидались байты кадра", null); return@setMethodCallHandler }
                        w.post {
                            val enc = encoder
                            if (enc == null) { fail(result, IllegalStateException("Энкодер не запущен")); return@post }
                            try { enc.feedFrame(bytes); ok(result, true) }
                            catch (e: Throwable) { abortOnWorker(); fail(result, e) }
                        }
                    }

                    "finish" -> {
                        w.post {
                            val enc = encoder
                            if (enc == null) { fail(result, IllegalStateException("Энкодер не запущен")); return@post }
                            try { val p = enc.finish(); encoder = null; ok(result, p) }
                            catch (e: Throwable) { abortOnWorker(); fail(result, e) }
                        }
                    }

                    "cancel" -> { w.post { abortOnWorker(); ok(result, true) } }

                    "muxAudio" -> {
                        val videoPath = call.argument<String>("videoPath")
                        val audioPath = call.argument<String>("audioPath")
                        val outputPath = call.argument<String>("outputPath")
                        val volume = (call.argument<Number>("volume"))?.toDouble() ?: 1.0
                        val startSec = (call.argument<Number>("startTime"))?.toDouble() ?: 0.0
                        val durationMs = call.argument<Int>("durationMs") ?: 0
                        if (videoPath.isNullOrEmpty() || audioPath.isNullOrEmpty() || outputPath.isNullOrEmpty() || durationMs <= 0) {
                            result.error("BAD_ARGS", "Неверные параметры muxAudio", null)
                            return@setMethodCallHandler
                        }
                        w.post {
                            try {
                                val p = AudioMuxer.mux(videoPath, audioPath, outputPath, volume, startSec, durationMs)
                                ok(result, p)
                            } catch (e: Throwable) { fail(result, e) }
                        }
                    }

                    "analyzeBeats" -> {
                        val audioPath = call.argument<String>("audioPath")
                        if (audioPath.isNullOrEmpty()) { result.error("BAD_ARGS", "Нет audioPath", null); return@setMethodCallHandler }
                        w.post {
                            try {
                                val r = BeatAnalyzer.analyze(audioPath)
                                val map = HashMap<String, Any?>()
                                map["beats"] = r.beats; map["bpm"] = r.bpm
                                map["waveform"] = r.waveform; map["durationSec"] = r.durationSec
                                map["isValid"] = r.isValid()
                                ok(result, map)
                            } catch (e: Throwable) { fail(result, e) }
                        }
                    }

                    // ✅ GIF
                    "gifStart" -> {
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        val fps = call.argument<Int>("fps") ?: 10
                        val path = call.argument<String>("path")
                        if (width <= 0 || height <= 0 || path.isNullOrEmpty()) {
                            result.error("BAD_ARGS", "Неверные параметры gifStart", null)
                            return@setMethodCallHandler
                        }
                        w.post {
                            try {
                                gif?.abort()
                                val delayCs = (100.0 / fps).toInt().coerceAtLeast(2)
                                val g = GifEncoder(width, height, delayCs, 0, path)
                                gif = g
                                ok(result, true)
                            } catch (e: Throwable) { gif?.abort(); gif = null; fail(result, e) }
                        }
                    }

                    "gifFrame" -> {
                        val bytes = call.arguments as? ByteArray
                        if (bytes == null) { result.error("BAD_ARGS", "Ожидались байты кадра", null); return@setMethodCallHandler }
                        w.post {
                            val g = gif
                            if (g == null) { fail(result, IllegalStateException("GIF не запущен")); return@post }
                            try { g.feedFrame(bytes); ok(result, true) }
                            catch (e: Throwable) { g.abort(); gif = null; fail(result, e) }
                        }
                    }

                    "gifFinish" -> {
                        w.post {
                            val g = gif
                            if (g == null) { fail(result, IllegalStateException("GIF не запущен")); return@post }
                            try { val p = g.finish(); gif = null; ok(result, p) }
                            catch (e: Throwable) { g.abort(); gif = null; fail(result, e) }
                        }
                    }

                    "gifCancel" -> { w.post { gif?.abort(); gif = null; ok(result, true) } }

                    else -> result.notImplemented()
                }
            }
    }

    private fun abortOnWorker() {
        try { encoder?.abort() } catch (_: Throwable) {}
        encoder = null
    }

    private fun ok(result: MethodChannel.Result, value: Any) { main.post { result.success(value) } }
    private fun fail(result: MethodChannel.Result, e: Throwable) {
        val msg = e.message ?: e.javaClass.simpleName
        main.post { result.error("ENCODER_ERROR", msg, null) }
    }

    override fun onDestroy() {
        try { worker?.post { abortOnWorker(); gif?.abort(); gif = null } } catch (_: Throwable) {}
        try { workerThread?.quitSafely() } catch (_: Throwable) {}
        workerThread = null; worker = null
        super.onDestroy()
    }
}