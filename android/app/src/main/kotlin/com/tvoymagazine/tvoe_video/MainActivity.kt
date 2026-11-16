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
                            } catch (e: Throwable) {
                                abortOnWorker()
                                fail(result, e)
                            }
                        }
                    }

                    "feedFrame" -> {
                        val bytes = call.arguments as? ByteArray
                        if (bytes == null) {
                            result.error("BAD_ARGS", "Ожидались байты кадра (Uint8List)", null)
                            return@setMethodCallHandler
                        }
                        w.post {
                            val enc = encoder
                            if (enc == null) {
                                fail(result, IllegalStateException("Энкодер не запущен"))
                                return@post
                            }
                            try {
                                enc.feedFrame(bytes)
                                ok(result, true)
                            } catch (e: Throwable) {
                                abortOnWorker()
                                fail(result, e)
                            }
                        }
                    }

                    "finish" -> {
                        w.post {
                            val enc = encoder
                            if (enc == null) {
                                fail(result, IllegalStateException("Энкодер не запущен"))
                                return@post
                            }
                            try {
                                val path = enc.finish()
                                encoder = null
                                ok(result, path)
                            } catch (e: Throwable) {
                                abortOnWorker()
                                fail(result, e)
                            }
                        }
                    }

                    "cancel" -> {
                        w.post {
                            abortOnWorker()
                            ok(result, true)
                        }
                    }

                    // ✅ ШАГ 2: добавление звука
                    "muxAudio" -> {
                        val videoPath = call.argument<String>("videoPath")
                        val audioPath = call.argument<String>("audioPath")
                        val outputPath = call.argument<String>("outputPath")
                        val volume = (call.argument<Number>("volume"))?.toDouble() ?: 1.0
                        val startSec = (call.argument<Number>("startTime"))?.toDouble() ?: 0.0
                        val durationMs = call.argument<Int>("durationMs") ?: 0

                        if (videoPath.isNullOrEmpty() ||
                            audioPath.isNullOrEmpty() ||
                            outputPath.isNullOrEmpty() ||
                            durationMs <= 0
                        ) {
                            result.error("BAD_ARGS", "Неверные параметры muxAudio", null)
                            return@setMethodCallHandler
                        }

                        w.post {
                            try {
                                val path = AudioMuxer.mux(
                                    videoPath = videoPath,
                                    audioPath = audioPath,
                                    outputPath = outputPath,
                                    volume = volume,
                                    startSec = startSec,
                                    durationMs = durationMs
                                )
                                ok(result, path)
                            } catch (e: Throwable) {
                                fail(result, e)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** Вызывать ТОЛЬКО на worker-потоке */
    private fun abortOnWorker() {
        try { encoder?.abort() } catch (_: Throwable) {}
        encoder = null
    }

    private fun ok(result: MethodChannel.Result, value: Any) {
        main.post { result.success(value) }
    }

    private fun fail(result: MethodChannel.Result, e: Throwable) {
        val msg = e.message ?: e.javaClass.simpleName
        main.post { result.error("ENCODER_ERROR", msg, null) }
    }

    override fun onDestroy() {
        try { worker?.post { abortOnWorker() } } catch (_: Throwable) {}
        try { workerThread?.quitSafely() } catch (_: Throwable) {}
        workerThread = null
        worker = null
        super.onDestroy()
    }
}