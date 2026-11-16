package com.tvoymagazine.tvoe_video

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Аппаратный кодировщик RGBA-кадров в H.264 MP4.
 * ВСЕ методы должны вызываться из одного и того же потока (EGL-контекст привязан к потоку).
 */
class VideoEncoder(
    private val width: Int,
    private val height: Int,
    private val fps: Int,
    private val bitrate: Int,
    private val outputPath: String
) {
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var inputSurface: Surface? = null
    private var trackIndex = -1
    private var muxerStarted = false
    private var samplesWritten = 0
    private var frameIndex = 0L
    private var released = false

    // EGL / GL
    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var program = 0
    private var textureId = 0
    private var aPosition = 0
    private var aTexCoord = 0
    private var uTexture = 0
    private var texAllocated = false
    private var uploadBuffer: ByteBuffer? = null

    // x, y, u, v  — нижний левый угол экрана берёт нижнюю строку картинки (без переворота)
    private val quad: FloatBuffer = ByteBuffer
        .allocateDirect(4 * 4 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            put(floatArrayOf(
                -1f, -1f, 0f, 1f,
                 1f, -1f, 1f, 1f,
                -1f,  1f, 0f, 0f,
                 1f,  1f, 1f, 0f
            ))
            position(0)
        }

    val framesWritten: Long get() = frameIndex

    // ==========================================
    // START
    // ==========================================
    fun start() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height)
        format.setInteger(
            MediaFormat.KEY_COLOR_FORMAT,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
        )
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
        format.setInteger(MediaFormat.KEY_FRAME_RATE, fps)
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        try {
            format.setInteger(
                MediaFormat.KEY_BITRATE_MODE,
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR
            )
        } catch (_: Throwable) {}

        val c = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        try {
            c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = c.createInputSurface()
            c.start()
            codec = c
        } catch (e: Throwable) {
            try { c.release() } catch (_: Throwable) {}
            throw RuntimeException("Не удалось настроить энкодер ${width}x$height: ${e.message}", e)
        }

        muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        initEgl()
        initGl()
    }

    // ==========================================
    // FEED ONE RGBA FRAME
    // ==========================================
    fun feedFrame(bytes: ByteArray) {
        if (released) throw IllegalStateException("Энкодер уже закрыт")
        val expected = width * height * 4
        if (bytes.size != expected) {
            throw IllegalArgumentException("Размер кадра ${bytes.size}, ожидалось $expected")
        }

        var bb = uploadBuffer
        if (bb == null || bb.capacity() != bytes.size) {
            bb = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
            uploadBuffer = bb
        }
        bb.clear()
        bb.put(bytes)
        bb.position(0)

        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        if (!texAllocated) {
            GLES20.glTexImage2D(
                GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, width, height, 0,
                GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, bb
            )
            texAllocated = true
        } else {
            GLES20.glTexSubImage2D(
                GLES20.GL_TEXTURE_2D, 0, 0, 0, width, height,
                GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, bb
            )
        }
        checkGl("upload")

        GLES20.glViewport(0, 0, width, height)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        GLES20.glUseProgram(program)
        quad.position(0)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 16, quad)
        GLES20.glEnableVertexAttribArray(aPosition)
        quad.position(2)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 16, quad)
        GLES20.glEnableVertexAttribArray(aTexCoord)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glUniform1i(uTexture, 0)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        checkGl("draw")

        val ptsNanos = frameIndex * 1_000_000_000L / fps
        EGLExt.eglPresentationTimeANDROID(eglDisplay, eglSurface, ptsNanos)
        if (!EGL14.eglSwapBuffers(eglDisplay, eglSurface)) {
            throw RuntimeException("eglSwapBuffers failed: 0x${Integer.toHexString(EGL14.eglGetError())}")
        }

        frameIndex++
        drain(false)
    }

    // ==========================================
    // FINISH
    // ==========================================
    fun finish(): String {
        if (released) return outputPath
        if (frameIndex == 0L) {
            abort()
            throw IllegalStateException("Не передано ни одного кадра")
        }
        codec?.signalEndOfInputStream()
        drain(true)
        release(deleteFile = false)
        return outputPath
    }

    fun abort() {
        release(deleteFile = true)
    }

    // ==========================================
    // DRAIN ENCODER OUTPUT → MUXER
    // ==========================================
    private fun drain(waitForEos: Boolean) {
        val c = codec ?: return
        val m = muxer ?: return
        val info = MediaCodec.BufferInfo()
        val deadline = System.currentTimeMillis() + 20_000L

        while (true) {
            val status = c.dequeueOutputBuffer(info, if (waitForEos) 10_000L else 0L)

            if (status == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                if (muxerStarted) throw IllegalStateException("Формат изменился дважды")
                trackIndex = m.addTrack(c.outputFormat)
                m.start()
                muxerStarted = true
            } else if (status >= 0) {
                val buf = c.getOutputBuffer(status)
                if (buf == null) {
                    c.releaseOutputBuffer(status, false)
                    continue
                }
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    info.size = 0
                }
                if (info.size > 0 && muxerStarted) {
                    buf.position(info.offset)
                    buf.limit(info.offset + info.size)
                    m.writeSampleData(trackIndex, buf, info)
                    samplesWritten++
                }
                c.releaseOutputBuffer(status, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
            } else {
                // INFO_TRY_AGAIN_LATER
                if (!waitForEos) return
                if (System.currentTimeMillis() > deadline) {
                    throw RuntimeException("Таймаут ожидания конца потока от энкодера")
                }
            }
        }
    }

    // ==========================================
    // EGL / GL
    // ==========================================
    private fun initEgl() {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) throw RuntimeException("eglGetDisplay failed")

        val version = IntArray(2)
        if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
            throw RuntimeException("eglInitialize failed")
        }

        val configAttribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
            0x3142, 1, // EGL_RECORDABLE_ANDROID
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        if (!EGL14.eglChooseConfig(eglDisplay, configAttribs, 0, configs, 0, 1, numConfigs, 0)
            || numConfigs[0] == 0
        ) {
            throw RuntimeException("eglChooseConfig не нашёл подходящей конфигурации")
        }
        val config = configs[0]!!

        eglContext = EGL14.eglCreateContext(
            eglDisplay, config, EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0
        )
        if (eglContext == EGL14.EGL_NO_CONTEXT) throw RuntimeException("eglCreateContext failed")

        eglSurface = EGL14.eglCreateWindowSurface(
            eglDisplay, config, inputSurface!!, intArrayOf(EGL14.EGL_NONE), 0
        )
        if (eglSurface == EGL14.EGL_NO_SURFACE) throw RuntimeException("eglCreateWindowSurface failed")

        if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
            throw RuntimeException("eglMakeCurrent failed")
        }
    }

    private fun initGl() {
        val vs = """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = aTexCoord;
            }
        """.trimIndent()

        val fs = """
            precision mediump float;
            varying vec2 vTexCoord;
            uniform sampler2D uTexture;
            void main() {
                vec4 c = texture2D(uTexture, vTexCoord);
                gl_FragColor = vec4(c.rgb, 1.0);
            }
        """.trimIndent()

        program = buildProgram(vs, fs)
        aPosition = GLES20.glGetAttribLocation(program, "aPosition")
        aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
        uTexture = GLES20.glGetUniformLocation(program, "uTexture")

        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        textureId = ids[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        checkGl("initGl")
    }

    private fun buildProgram(vsSrc: String, fsSrc: String): Int {
        val vs = compileShader(GLES20.GL_VERTEX_SHADER, vsSrc)
        val fs = compileShader(GLES20.GL_FRAGMENT_SHADER, fsSrc)
        val p = GLES20.glCreateProgram()
        GLES20.glAttachShader(p, vs)
        GLES20.glAttachShader(p, fs)
        GLES20.glLinkProgram(p)
        val status = IntArray(1)
        GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(p)
            GLES20.glDeleteProgram(p)
            throw RuntimeException("Ошибка линковки шейдеров: $log")
        }
        GLES20.glDeleteShader(vs)
        GLES20.glDeleteShader(fs)
        return p
    }

    private fun compileShader(type: Int, src: String): Int {
        val s = GLES20.glCreateShader(type)
        GLES20.glShaderSource(s, src)
        GLES20.glCompileShader(s)
        val status = IntArray(1)
        GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(s)
            GLES20.glDeleteShader(s)
            throw RuntimeException("Ошибка компиляции шейдера: $log")
        }
        return s
    }

    private fun checkGl(where: String) {
        val err = GLES20.glGetError()
        if (err != GLES20.GL_NO_ERROR) {
            throw RuntimeException("GL ошибка в $where: 0x${Integer.toHexString(err)}")
        }
    }

    // ==========================================
    // RELEASE
    // ==========================================
    private fun release(deleteFile: Boolean) {
        if (released) return
        released = true

        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            try {
                EGL14.eglMakeCurrent(
                    eglDisplay, EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT
                )
            } catch (_: Throwable) {}
            try { if (eglSurface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(eglDisplay, eglSurface) } catch (_: Throwable) {}
            try { if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(eglDisplay, eglContext) } catch (_: Throwable) {}
            try { EGL14.eglTerminate(eglDisplay) } catch (_: Throwable) {}
        }
        eglSurface = EGL14.EGL_NO_SURFACE
        eglContext = EGL14.EGL_NO_CONTEXT
        eglDisplay = EGL14.EGL_NO_DISPLAY

        try { inputSurface?.release() } catch (_: Throwable) {}
        inputSurface = null

        try { codec?.stop() } catch (_: Throwable) {}
        try { codec?.release() } catch (_: Throwable) {}
        codec = null

        val m = muxer
        if (m != null) {
            if (muxerStarted && samplesWritten > 0 && !deleteFile) {
                try { m.stop() } catch (_: Throwable) {}
            }
            try { m.release() } catch (_: Throwable) {}
        }
        muxer = null
        muxerStarted = false

        uploadBuffer = null

        if (deleteFile) {
            try {
                val f = File(outputPath)
                if (f.exists()) f.delete()
            } catch (_: Throwable) {}
        }
    }
}