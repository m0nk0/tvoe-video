package com.tvoymagazine.tvoe_video

import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Стриминговый GIF89a-энкодер (без зависимостей).
 * Палитра: 6x6x6 куб (216) + 40 серых = 256.
 * Ordered dither (Bayer 4x4) против бандинга. LZW с clear-кодами.
 * Все методы вызывать из worker-потока.
 */
class GifEncoder(
    private val width: Int,
    private val height: Int,
    private val delayCs: Int,
    private val loop: Int,
    private val path: String
) {
    private val out = BufferedOutputStream(FileOutputStream(path), 1 shl 16)
    private val palette = buildPalette()
    private val indices = ByteArray(width * height)
    private var closed = false

    private val bayer = arrayOf(
        intArrayOf(0, 8, 2, 10),
        intArrayOf(12, 4, 14, 6),
        intArrayOf(3, 11, 1, 9),
        intArrayOf(15, 7, 13, 5)
    )

    init {
        writeHeader()
    }

    private fun buildPalette(): ByteArray {
        val p = ByteArray(256 * 3)
        var i = 0
        for (r in 0..5) for (g in 0..5) for (b in 0..5) {
            p[i * 3] = (r * 51).toByte()
            p[i * 3 + 1] = (g * 51).toByte()
            p[i * 3 + 2] = (b * 51).toByte()
            i++
        }
        for (g in 0..39) {
            val v = (g * 255.0 / 39.0).roundToInt()
            p[i * 3] = v.toByte(); p[i * 3 + 1] = v.toByte(); p[i * 3 + 2] = v.toByte()
            i++
        }
        return p
    }

    private fun w16(v: Int) {
        out.write(v and 0xFF)
        out.write((v shr 8) and 0xFF)
    }

    private fun writeHeader() {
        out.write("GIF89a".toByteArray(Charsets.US_ASCII))
        w16(width); w16(height)
        out.write(0xF7) // GCT flag + color res 8 + size 256
        out.write(0)    // bg index
        out.write(0)    // aspect
        out.write(palette)
        // NETSCAPE2.0 loop extension
        out.write(0x21); out.write(0xFF); out.write(0x0B)
        out.write("NETSCAPE2.0".toByteArray(Charsets.US_ASCII))
        out.write(0x03); out.write(0x01)
        w16(loop)
        out.write(0x00)
    }

    fun feedFrame(rgba: ByteArray) {
        if (closed) throw IllegalStateException("GIF уже закрыт")
        val expected = width * height * 4
        if (rgba.size != expected) throw IllegalArgumentException("frame ${rgba.size} != $expected")

        // Квантование + ordered dither
        var p = 0
        for (y in 0 until height) {
            val row = bayer[y and 3]
            for (x in 0 until width) {
                val off = ((row[x and 3] / 16.0) - 0.5) * 25.5
                // ✅ Исправление: Byte → Int через and 0xFF (0..255 без знака)
                val r = rgba[p].toInt() and 0xFF
                val g = rgba[p + 1].toInt() and 0xFF
                val b = rgba[p + 2].toInt() and 0xFF
                val ri = ((r + off).roundToInt().coerceIn(0, 255)) / 51
                val gi = ((g + off).roundToInt().coerceIn(0, 255)) / 51
                val bi = ((b + off).roundToInt().coerceIn(0, 255)) / 51
                val mx = max(r, max(g, b)); val mn = min(r, min(g, b))
                val idx = if (mx - mn < 12) {
                    216 + (((r + g + b) / 3.0) / 255.0 * 39.0).roundToInt().coerceIn(0, 39)
                } else {
                    ri * 36 + gi * 6 + bi
                }
                indices[y * width + x] = idx.toByte()
                p += 4
            }
        }

        // Graphic Control Extension
        out.write(0x21); out.write(0xF9); out.write(0x04)
        out.write(0x04) // disposal = background
        w16(delayCs)
        out.write(0x00) // transparent index (не используется)
        out.write(0x00)
        // Image Descriptor
        out.write(0x2C)
        w16(0); w16(0); w16(width); w16(height)
        out.write(0x00) // no local table, no interlace
        // LZW
        out.write(8) // min code size
        val comp = lzw(indices, 8)
        var off = 0
        while (off < comp.size) {
            val n = min(255, comp.size - off)
            out.write(n)
            out.write(comp, off, n)
            off += n
        }
        out.write(0x00) // block terminator
    }

    fun finish(): String {
        if (!closed) {
            out.write(0x3B) // trailer
            out.flush(); out.close()
            closed = true
        }
        return path
    }

    fun abort() {
        if (!closed) {
            try { out.flush(); out.close() } catch (_: Throwable) {}
            closed = true
        }
        try { File(path).delete() } catch (_: Throwable) {}
    }

    // ==========================================
    // LZW (GIF variant, LSB-first)
    // ==========================================
    private class BitWriter {
        private val buf = ArrayList<Byte>()
        private var acc = 0
        private var nbits = 0
        fun write(code: Int, size: Int) {
            acc = acc or (code shl nbits)
            nbits += size
            while (nbits >= 8) {
                buf.add((acc and 0xFF).toByte())
                acc = acc ushr 8
                nbits -= 8
            }
        }
        fun flush() {
            if (nbits > 0) { buf.add((acc and 0xFF).toByte()); acc = 0; nbits = 0 }
        }
        fun toByteArray(): ByteArray = buf.toByteArray()
    }

    private fun lzw(data: ByteArray, minCodeSize: Int): ByteArray {
        val clear = 1 shl minCodeSize
        val eoi = clear + 1
        var codeSize = minCodeSize + 1
        var next = eoi + 1
        val dict = HashMap<Int, Int>()
        val bw = BitWriter()
        bw.write(clear, codeSize)
        if (data.isEmpty()) { bw.write(eoi, codeSize); bw.flush(); return bw.toByteArray() }
        var prefix = data[0].toInt() and 0xFF
        for (i in 1 until data.size) {
            val k = data[i].toInt() and 0xFF
            val key = (prefix shl 8) or k
            val existing = dict[key]
            if (existing != null) {
                prefix = existing
            } else {
                bw.write(prefix, codeSize)
                if (next < 4096) {
                    dict[key] = next
                    if (next == (1 shl codeSize) && codeSize < 12) codeSize++
                    next++
                } else {
                    bw.write(clear, codeSize)
                    dict.clear()
                    next = eoi + 1
                    codeSize = minCodeSize + 1
                }
                prefix = k
            }
        }
        bw.write(prefix, codeSize)
        bw.write(eoi, codeSize)
        bw.flush()
        return bw.toByteArray()
    }
}