#!/usr/bin/env bash
# IR Lamba Bulucu v3 - proje dosyalarini olusturur (GitHub Actions bu dosyayi calistirir)
set -e
mkdir -p "."
cat > "settings.gradle.kts" <<'__IR_EOF__'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "IRBulucu"
__IR_EOF__
mkdir -p "."
cat > "build.gradle.kts" <<'__IR_EOF__'
plugins {
    id("com.android.application") version "8.5.2"
    id("org.jetbrains.kotlin.android") version "1.9.24"
}

android {
    namespace = "com.example.irbulucu"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.irbulucu"
        minSdk = 21
        targetSdk = 34
        versionCode = 3
        versionName = "3.0"
    }

    // Sabit imza: her derlemede ayni anahtar kullanilir, boylece uygulama
    // uzerine guncellenir ve kayitli kumandalar silinmez.
    signingConfigs {
        create("fixed") {
            storeFile = file("irbulucu.jks")
            storePassword = "android"
            keyAlias = "irbulucu"
            keyPassword = "android"
        }
    }
    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("fixed")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
}
__IR_EOF__
mkdir -p "."
cat > "gradle.properties" <<'__IR_EOF__'
android.useAndroidX=true
org.gradle.jvmargs=-Xmx2g
__IR_EOF__
mkdir -p "src/main"
cat > "src/main/AndroidManifest.xml" <<'__IR_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.TRANSMIT_IR" />
    <uses-feature
        android:name="android.hardware.consumerir"
        android:required="false" />

    <application
        android:allowBackup="true"
        android:label="IR Lamba Bulucu"
        android:theme="@style/Theme.AppCompat.DayNight.DarkActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
__IR_EOF__
mkdir -p "src/main/java/com/example/irbulucu"
cat > "src/main/java/com/example/irbulucu/IrCodes.kt" <<'__IR_EOF__'
package com.example.irbulucu

/** Desteklenen IR protokolleri ve taşıyıcı frekansları (Hz). */
enum class Proto(val title: String, val freq: Int) {
    NEC("NEC (LED/ucuz lamba)", 38000),
    SAMSUNG("Samsung", 38000),
    SONY("Sony SIRC", 40000),
    RC5("Philips RC5", 36000)
}

/** Tek bir kod. Pattern ihtiyaç olunca üretilir (hafıza tasarrufu). */
class CodeSpec(val proto: Proto, val addr: Int, val cmd: Int) {

    fun label(): String = "%s  adres=0x%02X  komut=0x%02X".format(proto.name, addr, cmd)

    fun pattern(): IntArray = when (proto) {
        Proto.NEC -> IrGen.nec(addr, cmd)
        Proto.SAMSUNG -> IrGen.samsung(addr, cmd)
        Proto.SONY -> IrGen.sony12(addr, cmd)
        Proto.RC5 -> IrGen.rc5(addr, cmd)
    }
}

object IrGen {

    // Panelin en üstünde gösterilen ana tuşlar
    const val KEY_ON = "POWER ON"
    const val KEY_OFF = "POWER OFF"
    const val KEY_DOWN = "BRIGHTNESS -"
    const val KEY_UP = "BRIGHTNESS +"

    val MAIN_KEYS: List<String> = listOf(KEY_ON, KEY_OFF, KEY_DOWN, KEY_UP)

    /** Tuş atarken sunulan varsayılan tuş adları (LED lamba kumandası düzeni). */
    val DEFAULT_KEYS: List<String> = listOf(
        KEY_ON, KEY_OFF, KEY_DOWN, KEY_UP,
        "RED", "GREEN", "BLUE", "YELLOW", "PURPLE",
        "DARK GREEN", "WHITE", "ORANGE",
        "6-COLOR ALTERNATION", "PINK", "LIGHT BLUE", "DARK YELLOW",
        "7 COLOR GRADIENT", "DEEP BLUE", "AZURE", "MAGENTA",
        "3 COLORS JUMP", "LIGHT GREEN", "LIGHT YELLOW", "7 COLORS JUMP"
    )

    /** Düğme üzerinde görünen kısa yazı (parlaklık tuşları + / − olarak). */
    fun keyLabel(name: String): String = when (name) {
        KEY_UP -> "+"
        KEY_DOWN -> "−"
        else -> name
    }

    /** Listelerde görünen açıklayıcı yazı. */
    fun keyPickerLabel(name: String): String = when (name) {
        KEY_UP -> "＋  Işık artır"
        KEY_DOWN -> "−  Işık azalt"
        else -> name
    }

    // En sık görülen NEC adresleri (LED şerit/ucuz lamba kumandaları çoğunlukla 0x00, 0x80, 0x40...)
    private val NEC_PRIORITY = intArrayOf(
        0x00, 0x80, 0x40, 0xC0, 0x20, 0xA0, 0x10, 0x08,
        0x04, 0x02, 0x01, 0x07, 0x0F, 0x1F, 0x3F, 0xFF
    )
    private val SAMSUNG_PRIORITY = intArrayOf(0x07, 0x00, 0x01, 0x08)
    private val SONY_PRIORITY = intArrayOf(1, 0, 2, 3, 4, 5, 6, 7)
    private val RC5_PRIORITY = intArrayOf(0, 1, 2, 3, 4, 5, 16, 17)

    private fun ordered(priority: IntArray, max: Int, full: Boolean): List<Int> {
        val set = LinkedHashSet<Int>()
        priority.forEach { set.add(it) }
        if (full) for (a in 0..max) set.add(a)
        return set.toList()
    }

    /** Bir protokolde adres başına kaç komut var. */
    fun cmdCount(p: Proto): Int = when (p) {
        Proto.NEC -> 256
        Proto.SAMSUNG -> 256
        Proto.SONY -> 128
        Proto.RC5 -> 64
    }

    /** Seçilen protokoller için denenecek kod listesini üretir. */
    fun generate(protos: Set<Proto>, full: Boolean): List<CodeSpec> {
        val out = ArrayList<CodeSpec>()
        if (Proto.NEC in protos) {
            for (a in ordered(NEC_PRIORITY, 255, full)) for (c in 0..255) out.add(CodeSpec(Proto.NEC, a, c))
        }
        if (Proto.SAMSUNG in protos) {
            for (a in ordered(SAMSUNG_PRIORITY, 255, full)) for (c in 0..255) out.add(CodeSpec(Proto.SAMSUNG, a, c))
        }
        if (Proto.SONY in protos) {
            for (a in ordered(SONY_PRIORITY, 31, full)) for (c in 0..127) out.add(CodeSpec(Proto.SONY, a, c))
        }
        if (Proto.RC5 in protos) {
            for (a in ordered(RC5_PRIORITY, 31, full)) for (c in 0..63) out.add(CodeSpec(Proto.RC5, a, c))
        }
        return out
    }

    // =====================================================================
    //  AÇIKLAMA / MARKA TAHMİNİ
    // =====================================================================

    /** Kodun ham veri baytlarını okunur biçimde verir. */
    fun dataBytes(p: Proto, addr: Int, cmd: Int): String = when (p) {
        Proto.NEC -> "%02X %02X %02X %02X  (adres, ~adres, komut, ~komut)".format(
            addr and 0xFF, addr.inv() and 0xFF, cmd and 0xFF, cmd.inv() and 0xFF
        )
        Proto.SAMSUNG -> "%02X %02X %02X %02X  (adres, adres, komut, ~komut)".format(
            addr and 0xFF, addr and 0xFF, cmd and 0xFF, cmd.inv() and 0xFF
        )
        Proto.SONY -> "12 bit: komut=%d (7 bit), adres=%d (5 bit)".format(cmd, addr)
        Proto.RC5 -> "14 bit: adres=%d (5 bit), komut=%d (6 bit)".format(addr, cmd)
    }

    /** Protokol + adrese göre olası cihaz ailesi. Marka/model kesin bilinemez, tahmindir. */
    fun guess(p: Proto, addr: Int): String = when (p) {
        Proto.NEC -> when (addr) {
            0x00 -> "Genel/markasız LED şerit-ampul kumandaları, MP3/araç ses ve mini fan kumandaları (en yaygın adres)"
            0x04 -> "LG TV/monitör ailesi"
            0x40 -> "Toshiba TV ailesi veya genel LED/ışık kumandaları"
            0x80, 0xC0 -> "Çin yapımı genel LED ışık, fan ve ses kumandaları"
            else -> "Bilinmeyen NEC adresi; markasız/ucuz ışık kumandası olma ihtimali yüksek"
        }
        Proto.SAMSUNG -> if (addr == 0x07) "Samsung TV ailesi" else "Samsung protokolü kullanan cihaz"
        Proto.SONY -> "Sony ailesi (adres 1 genelde TV, 2 video/VCR)"
        Proto.RC5 -> "Philips RC5 ailesi (adres 0 TV, 5 video, 16 amfi, 20 CD)"
    }

    /** Bir kodun tam açıklaması (ekranda gösterilir). */
    fun describe(p: Proto, addr: Int, cmd: Int): String {
        val pat = CodeSpec(p, addr, cmd).pattern()
        val ms = pat.sum() / 1000
        return "Protokol: " + p.name + " (" + (p.freq / 1000) + " kHz taşıyıcı)\n" +
            "Adres: 0x%02X (%d)\n".format(addr, addr) +
            "Komut: 0x%02X (%d)\n".format(cmd, cmd) +
            "Veri: " + dataBytes(p, addr, cmd) + "\n" +
            "Ham darbe: " + pat.size + " adet, yaklaşık " + ms + " ms\n" +
            "Olası cihaz: " + guess(p, addr) + "\n\n" +
            "Not: IR kodu marka/model adı taşımaz, yalnızca protokol ve adres taşır. " +
            "Cihaz tahmini adres tablosuna dayanır."
    }

    // =====================================================================
    //  PROTOKOL ÜRETİCİLERİ
    // =====================================================================

    // ---------------- NEC ----------------
    fun nec(addr: Int, cmd: Int): IntArray {
        val a = addr and 0xFF
        val c = cmd and 0xFF
        val data = a or ((a.inv() and 0xFF) shl 8) or (c shl 16) or ((c.inv() and 0xFF) shl 24)
        val p = ArrayList<Int>(67)
        p.add(9000); p.add(4500)
        for (i in 0 until 32) {
            p.add(560)
            p.add(if (((data ushr i) and 1) == 1) 1690 else 560)
        }
        p.add(560)
        return p.toIntArray()
    }

    // ---------------- Samsung ----------------
    fun samsung(addr: Int, cmd: Int): IntArray {
        val a = addr and 0xFF
        val c = cmd and 0xFF
        val data = a or (a shl 8) or (c shl 16) or ((c.inv() and 0xFF) shl 24)
        val p = ArrayList<Int>(67)
        p.add(4500); p.add(4500)
        for (i in 0 until 32) {
            p.add(560)
            p.add(if (((data ushr i) and 1) == 1) 1690 else 560)
        }
        p.add(560)
        return p.toIntArray()
    }

    // ---------------- Sony SIRC 12 bit (3 tekrar, 45 ms periyot) ----------------
    fun sony12(addr: Int, cmd: Int): IntArray {
        val frame = ArrayList<Int>()
        frame.add(2400); frame.add(600)
        for (i in 0 until 7) {
            frame.add(if (((cmd shr i) and 1) == 1) 1200 else 600)
            frame.add(600)
        }
        for (i in 0 until 5) {
            frame.add(if (((addr shr i) and 1) == 1) 1200 else 600)
            frame.add(600)
        }
        frame.removeAt(frame.size - 1) // sondaki boşluğu at
        val used = frame.sum()
        val out = ArrayList<Int>()
        for (n in 0 until 3) {
            out.addAll(frame)
            if (n < 2) out.add(maxOf(45000 - used, 600))
        }
        return out.toIntArray()
    }

    // ---------------- Philips RC5 (Manchester) ----------------
    fun rc5(addr: Int, cmd: Int): IntArray {
        val bits = ArrayList<Int>()
        bits.add(1); bits.add(1); bits.add(0) // start, start, toggle
        for (i in 4 downTo 0) bits.add((addr shr i) and 1)
        for (i in 5 downTo 0) bits.add((cmd shr i) and 1)

        val levels = ArrayList<Boolean>() // true = taşıyıcı var (mark)
        for (b in bits) {
            if (b == 1) { levels.add(false); levels.add(true) }
            else { levels.add(true); levels.add(false) }
        }
        val runs = ArrayList<Pair<Boolean, Int>>()
        for (lv in levels) {
            if (runs.isNotEmpty() && runs.last().first == lv) {
                runs[runs.size - 1] = Pair(lv, runs.last().second + 889)
            } else {
                runs.add(Pair(lv, 889))
            }
        }
        if (!runs.first().first) runs.removeAt(0)
        if (!runs.last().first) runs.removeAt(runs.size - 1)
        return IntArray(runs.size) { runs[it].second }
    }
}
__IR_EOF__
mkdir -p "src/main/java/com/example/irbulucu"
cat > "src/main/java/com/example/irbulucu/RemoteStore.kt" <<'__IR_EOF__'
package com.example.irbulucu

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Kumandadaki tek bir tuş. cmd = -1 ise henüz öğrenilmemiş. */
class Key(var name: String, var cmd: Int)

/** Bulunan adres üzerinden çalışan tam kumanda (protokol + adres + tuşlar). */
class Remote(
    val id: Long,
    var name: String,
    val proto: Proto,
    val addr: Int,
    val keys: MutableList<Key>,
    var lastPos: Int = -1 // tuş öğretirken kalınan son komut numarası
) {
    fun spec(cmd: Int): CodeSpec = CodeSpec(proto, addr, cmd)

    fun key(keyName: String): Key? = keys.firstOrNull { it.name == keyName }

    /** Açma, kapama, ışık azalt, ışık artır tuşları her zaman listede bulunur. */
    fun ensureMain() {
        for (n in IrGen.MAIN_KEYS) {
            if (key(n) == null) keys.add(Key(n, -1))
        }
    }

    fun toJson(): JSONObject {
        val arr = JSONArray()
        for (k in keys) arr.put(JSONObject().put("n", k.name).put("c", k.cmd))
        return JSONObject()
            .put("id", id)
            .put("name", name)
            .put("proto", proto.name)
            .put("addr", addr)
            .put("lp", lastPos)
            .put("keys", arr)
    }

    companion object {
        fun create(
            name: String,
            proto: Proto,
            addr: Int,
            foundCmd: Int,
            foundKey: String,
            id: Long
        ): Remote {
            val keys = ArrayList<Key>()
            for (n in IrGen.MAIN_KEYS) keys.add(Key(n, -1))
            val existing = keys.firstOrNull { it.name == foundKey }
            if (existing != null) {
                existing.cmd = foundCmd
            } else {
                keys.add(Key(foundKey, foundCmd))
            }
            return Remote(id, name, proto, addr, keys, foundCmd)
        }

        fun fromJson(o: JSONObject): Remote? {
            return try {
                val arr = o.getJSONArray("keys")
                val keys = MutableList(arr.length()) {
                    val k = arr.getJSONObject(it)
                    Key(k.getString("n"), k.getInt("c"))
                }
                var lp = o.optInt("lp", -1)
                if (lp < 0) {
                    lp = keys.firstOrNull { it.cmd >= 0 }?.cmd ?: -1
                }
                val r = Remote(
                    o.getLong("id"),
                    o.getString("name"),
                    Proto.valueOf(o.getString("proto")),
                    o.getInt("addr"),
                    keys,
                    lp
                )
                r.ensureMain()
                r
            } catch (e: Exception) {
                null
            }
        }
    }
}

class RemoteStore(ctx: Context) {

    private val prefs = ctx.getSharedPreferences("ir_codes", Context.MODE_PRIVATE)

    /** Kayıtlı kumandaları yükler. Eski sürümde kaydedilen kodlar otomatik dönüştürülür. */
    fun load(): MutableList<Remote> {
        val out = ArrayList<Remote>()
        var migrated = false
        try {
            val arr = JSONArray(prefs.getString("list", "[]"))
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val r = Remote.fromJson(o)
                if (r != null) {
                    out.add(r)
                } else {
                    val legacy = migrateLegacy(o, i)
                    if (legacy != null) {
                        out.add(legacy)
                        migrated = true
                    }
                }
            }
        } catch (e: Exception) {
            // bozuk veri: boş liste dön
        }
        if (migrated) save(out)
        return out
    }

    fun save(list: List<Remote>) {
        val arr = JSONArray()
        for (r in list) arr.put(r.toJson())
        prefs.edit().putString("list", arr.toString()).apply()
    }

    fun upsert(r: Remote) {
        val list = load()
        val i = list.indexOfFirst { it.id == r.id }
        if (i >= 0) {
            list[i] = r
        } else {
            list.add(r)
        }
        save(list)
    }

    fun delete(id: Long) {
        save(load().filter { it.id != id })
    }

    // Eski sürüm kaydı: {"name":..,"label":"NEC  adres=0x00  komut=0x09", "pattern":[..]}
    private fun migrateLegacy(o: JSONObject, idx: Int): Remote? {
        val label = o.optString("label", "")
        val m = Regex("""(\w+)\s+adres=0x([0-9A-Fa-f]+)\s+komut=0x([0-9A-Fa-f]+)""").find(label)
            ?: return null
        val proto = try {
            Proto.valueOf(m.groupValues[1])
        } catch (e: Exception) {
            return null
        }
        val addr = m.groupValues[2].toInt(16)
        val cmd = m.groupValues[3].toInt(16)
        return Remote.create(
            o.optString("name", "Lamba"), proto, addr, cmd, IrGen.KEY_ON,
            System.currentTimeMillis() + idx
        )
    }
}

/** Kumanda hakkında ayrıntılı açıklama: protokol, adres, tahmini cihaz ve öğrenilen tuş kodları. */
fun remoteInfoText(r: Remote): String {
    val learned = r.keys.filter { it.cmd >= 0 }
    val sb = StringBuilder()
    sb.append("Kumanda: ").append(r.name).append("\n\n")
    if (learned.isNotEmpty()) {
        sb.append(IrGen.describe(r.proto, r.addr, learned[0].cmd)).append("\n\n")
    } else {
        sb.append("Protokol: ").append(r.proto.name).append("\n")
        sb.append("Adres: 0x").append("%02X".format(r.addr)).append("\n")
        sb.append("Olası cihaz: ").append(IrGen.guess(r.proto, r.addr)).append("\n\n")
    }
    sb.append("Öğrenilen tuşlar (").append(learned.size).append("):\n")
    for (k in learned) {
        sb.append("• ").append(IrGen.keyPickerLabel(k.name)).append("  →  0x")
            .append("%02X".format(k.cmd)).append(" (").append(k.cmd).append(")\n")
    }
    return sb.toString()
}
__IR_EOF__
mkdir -p "src/main/java/com/example/irbulucu"
cat > "src/main/java/com/example/irbulucu/RemoteCardView.kt" <<'__IR_EOF__'
package com.example.irbulucu

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import android.view.View

/**
 * Yatay bir IR kumandası çizer: solda güç düğmesi, ortada kumandaya verilen ad,
 * sağda renk tuşları ve en uçta IR ledi.
 */
class RemoteCardView(ctx: Context) : View(ctx) {

    private var title = ""
    private var subtitle = ""
    private val d = ctx.resources.displayMetrics.density

    private val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val symPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val subPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val tmp = RectF()

    private val dotColors = intArrayOf(
        Color.parseColor("#E53935"), Color.parseColor("#43A047"), Color.parseColor("#1E88E5"),
        Color.parseColor("#FDD835"), Color.parseColor("#8E24AA"), Color.parseColor("#ECEFF1")
    )

    init {
        isClickable = true
        setLayerType(LAYER_TYPE_SOFTWARE, null)

        linePaint.style = Paint.Style.STROKE
        linePaint.strokeWidth = 1.5f * d

        symPaint.style = Paint.Style.STROKE
        symPaint.strokeWidth = 2.4f * d
        symPaint.strokeCap = Paint.Cap.ROUND
        symPaint.color = Color.WHITE

        titlePaint.color = Color.WHITE
        titlePaint.textSize = 20f * d
        titlePaint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)

        subPaint.color = Color.parseColor("#B4B4BE")
        subPaint.textSize = 12f * d
    }

    fun setInfo(t: String, s: String) {
        title = t
        subtitle = s
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        setMeasuredDimension(w, (116 * d).toInt())
    }

    override fun drawableStateChanged() {
        super.drawableStateChanged()
        invalidate()
    }

    override fun onDraw(c: Canvas) {
        super.onDraw(c)
        val w = width.toFloat()
        val h = height.toFloat()
        val pad = 8f * d
        rect.set(pad, pad, w - pad, h - pad - 4f * d)
        val radius = rect.height() * 0.30f
        val cy = rect.centerY()

        // --- Gövde + gölge ---
        bodyPaint.setShadowLayer(9f * d, 0f, 3f * d, Color.argb(140, 0, 0, 0))
        val topColor = if (isPressed) Color.parseColor("#4C4C55") else Color.parseColor("#3E3E46")
        bodyPaint.shader = LinearGradient(
            0f, rect.top, 0f, rect.bottom,
            topColor, Color.parseColor("#1B1B1F"), Shader.TileMode.CLAMP
        )
        c.drawRoundRect(rect, radius, radius, bodyPaint)

        // Kenar çizgisi
        linePaint.color = Color.parseColor("#63636D")
        c.drawRoundRect(rect, radius, radius, linePaint)

        // İç parlama
        tmp.set(rect.left + 3f * d, rect.top + 3f * d, rect.right - 3f * d, rect.bottom - 3f * d)
        linePaint.color = Color.argb(28, 255, 255, 255)
        c.drawRoundRect(tmp, radius - 3f * d, radius - 3f * d, linePaint)

        // --- Güç düğmesi (solda) ---
        val pr = 17f * d
        val pcx = rect.left + 20f * d + pr
        fillPaint.shader = RadialGradient(
            pcx - pr * 0.3f, cy - pr * 0.3f, pr * 1.4f,
            Color.parseColor("#FF6B6B"), Color.parseColor("#A61B1B"), Shader.TileMode.CLAMP
        )
        c.drawCircle(pcx, cy, pr, fillPaint)
        fillPaint.shader = null
        linePaint.color = Color.argb(90, 255, 255, 255)
        c.drawCircle(pcx, cy, pr, linePaint)

        val sr = 6.5f * d
        tmp.set(pcx - sr, cy - sr + 1.5f * d, pcx + sr, cy + sr + 1.5f * d)
        c.drawArc(tmp, -60f, 300f, false, symPaint)
        c.drawLine(pcx, cy - 8f * d, pcx, cy - 0.5f * d, symPaint)

        // --- IR ledi (en sağda) ---
        val irW = 9f * d
        val irH = 34f * d
        val irRight = rect.right - 14f * d
        tmp.set(irRight - irW, cy - irH / 2f, irRight, cy + irH / 2f)
        fillPaint.color = Color.parseColor("#0C0C0E")
        c.drawRoundRect(tmp, 4f * d, 4f * d, fillPaint)
        fillPaint.color = Color.parseColor("#9B1C1C")
        c.drawCircle(irRight - irW / 2f, cy, 2.4f * d, fillPaint)
        fillPaint.color = Color.argb(140, 255, 255, 255)
        c.drawCircle(irRight - irW / 2f - 0.7f * d, cy - 0.7f * d, 0.9f * d, fillPaint)

        // --- Renkli tuşlar ---
        val rr = 6.5f * d
        val gap = 6f * d
        val clusterW = 3f * (2f * rr) + 2f * gap
        val clusterRight = irRight - irW - 14f * d
        val clusterLeft = clusterRight - clusterW
        val textLeft = pcx + pr + 16f * d
        val showDots = clusterLeft - textLeft > 70f * d
        val textRight: Float
        if (showDots) {
            textRight = clusterLeft - 12f * d
            for (i in 0 until 6) {
                val col = (i % 3).toFloat()
                val rowSign = if (i < 3) -1f else 1f
                val x = clusterLeft + rr + col * (2f * rr + gap)
                val y = cy + rowSign * (rr + gap / 2f)
                fillPaint.color = dotColors[i]
                c.drawCircle(x, y, rr, fillPaint)
                fillPaint.color = Color.argb(80, 255, 255, 255)
                c.drawCircle(x - rr * 0.3f, y - rr * 0.3f, rr * 0.38f, fillPaint)
            }
        } else {
            textRight = irRight - irW - 12f * d
        }

        // --- Ad ve alt bilgi ---
        val maxW = maxOf(textRight - textLeft, 10f * d)
        val t = TextUtils.ellipsize(title, titlePaint, maxW, TextUtils.TruncateAt.END).toString()
        val s = TextUtils.ellipsize(subtitle, subPaint, maxW, TextUtils.TruncateAt.END).toString()
        c.drawText(t, textLeft, cy - 2f * d, titlePaint)
        c.drawText(s, textLeft, cy + 18f * d, subPaint)
    }
}
__IR_EOF__
mkdir -p "src/main/java/com/example/irbulucu"
cat > "src/main/java/com/example/irbulucu/RemotePanel.kt" <<'__IR_EOF__'
package com.example.irbulucu

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog

// =========================================================================
//  ORTAK ARAYÜZ YARDIMCILARI
// =========================================================================

internal fun uiDp(a: Activity, v: Int): Int = (v * a.resources.displayMetrics.density).toInt()

internal fun uiToast(a: Activity, msg: String) {
    Toast.makeText(a, msg, Toast.LENGTH_SHORT).show()
}

internal fun uiText(
    a: Activity,
    text: String,
    size: Float,
    bold: Boolean = false,
    color: Int = Color.WHITE
): TextView {
    val tv = TextView(a)
    tv.text = text
    tv.textSize = size
    tv.setTextColor(color)
    if (bold) tv.setTypeface(tv.typeface, Typeface.BOLD)
    tv.setPadding(0, uiDp(a, 4), 0, uiDp(a, 4))
    return tv
}

/** Yuvarlak hap biçimli düğme (kumanda tuşu görünümü). */
internal fun uiPill(
    a: Activity,
    text: String,
    textSize: Float = 16f,
    normal: Int = Color.parseColor("#505050"),
    pressed: Int = Color.parseColor("#6E6E6E"),
    onClick: () -> Unit
): TextView {
    fun shape(c: Int): GradientDrawable {
        val g = GradientDrawable()
        g.setCornerRadius(uiDp(a, 28).toFloat())
        g.setColor(c)
        return g
    }

    val bg = StateListDrawable()
    bg.addState(intArrayOf(android.R.attr.state_pressed), shape(pressed))
    bg.addState(intArrayOf(), shape(normal))

    val tv = TextView(a)
    tv.text = text
    tv.textSize = textSize
    tv.setTextColor(Color.WHITE)
    tv.gravity = Gravity.CENTER
    tv.maxLines = 1
    tv.ellipsize = TextUtils.TruncateAt.END
    tv.setPadding(uiDp(a, 12), uiDp(a, 16), uiDp(a, 12), uiDp(a, 16))
    tv.background = bg
    tv.isClickable = true
    tv.setOnClickListener { onClick() }
    return tv
}

/** Yatay satırda eşit genişlikte hücre. */
internal fun uiCell(a: Activity): LinearLayout.LayoutParams {
    val lp = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
    val m = uiDp(a, 4)
    lp.setMargins(m, m, m, m)
    return lp
}

/** Dikey düzende tam genişlikte satır. */
internal fun uiRow(a: Activity): LinearLayout.LayoutParams {
    val lp = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT
    )
    val m = uiDp(a, 4)
    lp.setMargins(m, m, m, m)
    return lp
}

internal fun uiAsk(a: Activity, title: String, initial: String, onOk: (String) -> Unit) {
    val et = EditText(a)
    et.setText(initial)
    et.setSingleLine()
    et.setSelection(et.text.length)
    val box = LinearLayout(a)
    box.setPadding(uiDp(a, 20), uiDp(a, 8), uiDp(a, 20), 0)
    box.addView(
        et,
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
    )
    AlertDialog.Builder(a)
        .setTitle(title)
        .setView(box)
        .setPositiveButton("Tamam") { _, _ ->
            val s = et.text.toString().trim()
            if (s.isNotEmpty()) onOk(s)
        }
        .setNegativeButton("İptal", null)
        .show()
}

internal fun uiConfirm(a: Activity, msg: String, onYes: () -> Unit) {
    AlertDialog.Builder(a)
        .setMessage(msg)
        .setPositiveButton("Evet") { _, _ -> onYes() }
        .setNegativeButton("İptal", null)
        .show()
}

internal fun uiMessage(a: Activity, title: String, msg: String) {
    AlertDialog.Builder(a)
        .setTitle(title)
        .setMessage(msg)
        .setPositiveButton("Tamam", null)
        .show()
}

// =========================================================================
//  KUMANDA PANELİ
//  Üstte: POWER ON / POWER OFF, altında: ışık azalt (−) / ışık artır (+)
//  Sonra "Diğer tuşlar" bölümü: atanmış diğer tüm tuşlar.
// =========================================================================

class RemotePanel(
    private val act: Activity,
    private val store: RemoteStore,
    private val remote: Remote,
    private val transmit: (Int, IntArray) -> Boolean,
    private val onChanged: () -> Unit
) {
    private val dialog = Dialog(act)
    private val content = LinearLayout(act)
    private val card = RemoteCardView(act)
    private var showOthers = true

    fun show() {
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)

        val bg = GradientDrawable()
        bg.setColor(Color.parseColor("#3E3E3E"))
        val r = uiDp(act, 28).toFloat()
        bg.setCornerRadii(floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f))

        val root = LinearLayout(act)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(uiDp(act, 16), uiDp(act, 8), uiDp(act, 16), uiDp(act, 12))
        root.background = bg

        val handle = uiText(act, "⌄", 24f, false, Color.LTGRAY)
        handle.gravity = Gravity.CENTER
        handle.setOnClickListener { dialog.dismiss() }
        root.addView(handle)

        card.isClickable = false
        root.addView(
            card,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        val actions = LinearLayout(act)
        actions.orientation = LinearLayout.HORIZONTAL
        actions.addView(uiPill(act, "ⓘ Bilgi", 13f) { showInfo() }, uiCell(act))
        actions.addView(uiPill(act, "＋ Tuş öğret", 13f) { startLearn(null) }, uiCell(act))
        root.addView(actions)

        content.orientation = LinearLayout.VERTICAL
        val scroll = ScrollView(act)
        scroll.addView(content)
        root.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        render()
        dialog.setContentView(root)
        dialog.show()

        val w = dialog.window
        if (w != null) {
            w.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            w.setGravity(Gravity.BOTTOM)
            w.setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                (act.resources.displayMetrics.heightPixels * 0.90).toInt()
            )
        }
    }

    private fun updateCard() {
        val learned = remote.keys.count { it.cmd >= 0 }
        card.setInfo(
            remote.name,
            remote.proto.name + " • adres 0x" + "%02X".format(remote.addr) + " • " + learned + " tuş"
        )
    }

    private fun render() {
        updateCard()
        content.removeAllViews()

        // --- 1. satır: açma / kapama ---
        val r1 = LinearLayout(act)
        r1.orientation = LinearLayout.HORIZONTAL
        r1.addView(mainPill(IrGen.KEY_ON, "POWER ON", 18f, "#2E7D32", "#43A047"), uiCell(act))
        r1.addView(mainPill(IrGen.KEY_OFF, "POWER OFF", 18f, "#B71C1C", "#D32F2F"), uiCell(act))
        content.addView(r1)

        // --- 2. satır: ışık azalt / artır ---
        val r2 = LinearLayout(act)
        r2.orientation = LinearLayout.HORIZONTAL
        r2.addView(mainPill(IrGen.KEY_DOWN, IrGen.keyLabel(IrGen.KEY_DOWN), 30f, "#505050", "#6E6E6E"), uiCell(act))
        r2.addView(mainPill(IrGen.KEY_UP, IrGen.keyLabel(IrGen.KEY_UP), 30f, "#505050", "#6E6E6E"), uiCell(act))
        content.addView(r2)

        // --- Diğer tuşlar (alt menü) ---
        val others = remote.keys.filter { it.cmd >= 0 && it.name !in IrGen.MAIN_KEYS }
        val arrow = if (showOthers) "▴" else "▾"
        val header = uiText(act, "Diğer tuşlar (" + others.size + ")   " + arrow, 16f, true, Color.LTGRAY)
        header.setPadding(uiDp(act, 4), uiDp(act, 18), 0, uiDp(act, 8))
        header.setOnClickListener {
            showOthers = !showOthers
            render()
        }
        content.addView(header)

        if (showOthers) {
            if (others.isEmpty()) {
                content.addView(
                    uiText(
                        act,
                        "Henüz başka tuş atanmadı. “＋ Tuş öğret” ile renk ve mod tuşlarını ekleyin.",
                        13f, false, Color.GRAY
                    )
                )
            } else {
                for (pair in others.chunked(2)) {
                    val row = LinearLayout(act)
                    row.orientation = LinearLayout.HORIZONTAL
                    for (k in pair) row.addView(keyPill(k), uiCell(act))
                    if (pair.size == 1) row.addView(View(act), uiCell(act))
                    content.addView(row)
                }
            }
        }
    }

    private fun mainPill(name: String, label: String, size: Float, normal: String, pressed: String): TextView {
        val k = remote.key(name)
        val p = uiPill(act, label, size, Color.parseColor(normal), Color.parseColor(pressed)) {
            val key = remote.key(name)
            if (key != null) onKey(key)
        }
        if (k == null || k.cmd < 0) p.alpha = 0.45f
        p.setOnLongClickListener {
            val key = remote.key(name)
            if (key != null) keyMenu(key)
            true
        }
        return p
    }

    private fun keyPill(k: Key): TextView {
        val p = uiPill(act, IrGen.keyLabel(k.name), 16f) { onKey(k) }
        p.setOnLongClickListener {
            keyMenu(k)
            true
        }
        return p
    }

    private fun persist() {
        store.upsert(remote)
        render()
        onChanged()
    }

    private fun onKey(k: Key) {
        if (k.cmd < 0) {
            AlertDialog.Builder(act)
                .setTitle(IrGen.keyPickerLabel(k.name))
                .setMessage("Bu tuş henüz öğrenilmedi. Lambayı gözlemleyerek öğretelim mi?")
                .setPositiveButton("Öğret") { _, _ -> startLearn(k.name) }
                .setNegativeButton("İptal", null)
                .show()
            return
        }
        if (!transmit(remote.proto.freq, remote.spec(k.cmd).pattern())) {
            uiToast(act, "IR gönderilemedi")
        }
    }

    private fun keyMenu(k: Key) {
        val isMain = k.name in IrGen.MAIN_KEYS
        val items = if (isMain) {
            arrayOf("Komutu yeniden öğret", "Kod bilgisi", "Atamayı kaldır")
        } else {
            arrayOf("Komutu yeniden öğret", "Adını değiştir", "Kod bilgisi", "Sil")
        }
        AlertDialog.Builder(act)
            .setTitle(IrGen.keyPickerLabel(k.name))
            .setItems(items) { _, which ->
                if (isMain) {
                    when (which) {
                        0 -> startLearn(k.name)
                        1 -> showKeyInfo(k)
                        2 -> {
                            k.cmd = -1
                            persist()
                        }
                        else -> {}
                    }
                } else {
                    when (which) {
                        0 -> startLearn(k.name)
                        1 -> uiAsk(act, "Tuş adı", k.name) { n ->
                            k.name = n
                            persist()
                        }
                        2 -> showKeyInfo(k)
                        3 -> uiConfirm(act, "“" + k.name + "” tuşu silinsin mi?") {
                            remote.keys.remove(k)
                            persist()
                        }
                        else -> {}
                    }
                }
            }
            .show()
    }

    private fun showKeyInfo(k: Key) {
        if (k.cmd < 0) {
            uiMessage(act, IrGen.keyPickerLabel(k.name), "Bu tuş henüz öğrenilmedi.")
        } else {
            uiMessage(act, IrGen.keyPickerLabel(k.name), IrGen.describe(remote.proto, remote.addr, k.cmd))
        }
    }

    private fun showInfo() {
        uiMessage(act, remote.name, remoteInfoText(remote))
    }

    private fun startLearn(target: String?) {
        LearnSession(
            act, remote, target, transmit,
            { keyName, cmd ->
                val k = remote.key(keyName)
                if (k != null) {
                    k.cmd = cmd
                } else {
                    remote.keys.add(Key(keyName, cmd))
                }
                persist()
            },
            {
                store.upsert(remote)
                onChanged()
            }
        ).show()
    }
}

// =========================================================================
//  TUŞ ÖĞRETME (ELLE, TEK TEK)
//  Kullanıcı İleri ▶ / ◀ Geri ile komutları tek tek gönderir. Lamba bir
//  tepki verince (ör. yeşil) "Tuş ata"ya basıp hangi tuş olduğunu seçer.
// =========================================================================

class LearnSession(
    private val act: Activity,
    private val remote: Remote,
    private val target: String?,
    private val transmit: (Int, IntArray) -> Boolean,
    private val onAssign: (String, Int) -> Unit,
    private val onClose: () -> Unit
) {
    private val dialog = Dialog(act)
    private lateinit var tvCmd: TextView
    private lateinit var tvSub: TextView

    private val total = IrGen.cmdCount(remote.proto)
    private var pos = remote.lastPos.coerceIn(-1, total - 1)
    private var sent = false

    fun show() {
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)

        val root = LinearLayout(act)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(uiDp(act, 18), uiDp(act, 16), uiDp(act, 18), uiDp(act, 16))

        val title = if (target != null) {
            "“" + IrGen.keyPickerLabel(target) + "” tuşunu öğret"
        } else {
            "Tuş öğret"
        }
        root.addView(uiText(act, title, 20f, true))
        root.addView(uiText(act, remote.name, 13f, false, Color.LTGRAY))

        val hint = if (target != null) {
            "İleri ▶ ile komutları tek tek gönder. Lambada “" + IrGen.keyPickerLabel(target) +
                "” işlevi gerçekleşince aşağıdaki yeşil düğmeye bas."
        } else {
            "İleri ▶ ile komutları tek tek gönder. Lambada bir tepki görünce (ör. yeşil renk) " +
                "“Tuş ata”ya bas ve hangi tuş olduğunu seç. Sonra İleri ile devam et."
        }
        root.addView(uiText(act, hint, 13f, false, Color.LTGRAY))

        tvCmd = uiText(act, "", 26f, true)
        tvCmd.gravity = Gravity.CENTER
        root.addView(tvCmd)
        tvSub = uiText(act, "", 13f, false, Color.LTGRAY)
        tvSub.gravity = Gravity.CENTER
        root.addView(tvSub)

        val nav = LinearLayout(act)
        nav.orientation = LinearLayout.HORIZONTAL
        nav.addView(uiPill(act, "◀ Geri", 16f) { move(-1) }, uiCell(act))
        nav.addView(uiPill(act, "↻", 16f) { resend() }, uiCell(act))
        nav.addView(
            uiPill(act, "İleri ▶", 18f, Color.parseColor("#1565C0"), Color.parseColor("#1E88E5")) { move(1) },
            uiCell(act)
        )
        root.addView(nav)

        val jump = LinearLayout(act)
        jump.orientation = LinearLayout.HORIZONTAL
        jump.addView(uiPill(act, "⏪ −10", 13f) { move(-10) }, uiCell(act))
        jump.addView(uiPill(act, "+10 ⏩", 13f) { move(10) }, uiCell(act))
        root.addView(jump)

        val assignText = if (target != null) {
            "🎯 Bu komut “" + IrGen.keyPickerLabel(target) + "”"
        } else {
            "🎯 Tuş ata"
        }
        root.addView(
            uiPill(
                act, assignText, 17f,
                Color.parseColor("#2E7D32"), Color.parseColor("#43A047")
            ) { assign() },
            uiRow(act)
        )

        root.addView(uiPill(act, "Kapat", 14f) { dialog.dismiss() }, uiRow(act))

        val bg = GradientDrawable()
        bg.setColor(Color.parseColor("#2E2E2E"))
        bg.setCornerRadius(uiDp(act, 24).toFloat())
        val scroll = ScrollView(act)
        scroll.background = bg
        scroll.addView(root)

        refreshInfo()
        dialog.setContentView(scroll)
        dialog.setOnDismissListener {
            remote.lastPos = pos
            onClose()
        }
        dialog.show()

        val w = dialog.window
        if (w != null) {
            w.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            w.setLayout(
                (act.resources.displayMetrics.widthPixels * 0.94).toInt(),
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            w.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun refreshInfo() {
        if (pos < 0) {
            tvCmd.text = "—"
            tvSub.text = "Henüz komut gönderilmedi. İleri ▶ ile başla."
            return
        }
        tvCmd.text = "Komut 0x%02X  (%d)".format(pos, pos)
        val assigned = remote.keys.firstOrNull { it.cmd == pos }
        val assignedText = if (assigned != null) {
            "Atanmış: " + IrGen.keyPickerLabel(assigned.name)
        } else {
            "Atanmamış"
        }
        val sentText = if (sent) "" else "  •  (henüz gönderilmedi)"
        tvSub.text = "Sıra " + (pos + 1) + " / " + total + "  •  " + assignedText + sentText
    }

    private fun move(d: Int) {
        pos = (pos + d).coerceIn(0, total - 1)
        sendNow()
    }

    private fun resend() {
        if (pos < 0) {
            uiToast(act, "Önce İleri ▶ ile bir komut gönderin")
            return
        }
        sendNow()
    }

    private fun sendNow() {
        sent = true
        if (!transmit(remote.proto.freq, CodeSpec(remote.proto, remote.addr, pos).pattern())) {
            uiToast(act, "IR gönderilemedi")
        }
        refreshInfo()
    }

    private fun assign() {
        if (pos < 0 || !sent) {
            uiToast(act, "Önce İleri ▶ ile bir komut gönderin")
            return
        }
        val c = pos
        if (target != null) {
            assignTo(target, c)
            dialog.dismiss()
            return
        }
        pickKey(c)
    }

    private fun assignTo(name: String, c: Int) {
        onAssign(name, c)
        uiToast(act, IrGen.keyPickerLabel(name) + " ← 0x" + "%02X".format(c))
        refreshInfo()
    }

    private fun pickKey(c: Int) {
        val names = ArrayList<String>(IrGen.DEFAULT_KEYS)
        for (k in remote.keys) {
            if (k.name !in names) names.add(k.name)
        }
        val labels = ArrayList<String>()
        for (n in names) {
            val k = remote.key(n)
            val mark = if (k != null && k.cmd >= 0) "   ✓ 0x" + "%02X".format(k.cmd) else ""
            labels.add(IrGen.keyPickerLabel(n) + mark)
        }
        labels.add("✏️  Özel ad yaz…")

        AlertDialog.Builder(act)
            .setTitle("Bu komut hangi tuş?  (0x" + "%02X".format(c) + ")")
            .setItems(labels.toTypedArray()) { _, which ->
                if (which < names.size) {
                    assignTo(names[which], c)
                } else {
                    uiAsk(act, "Tuş adı", "") { n -> assignTo(n, c) }
                }
            }
            .setNegativeButton("İptal", null)
            .show()
    }
}
__IR_EOF__
mkdir -p "src/main/java/com/example/irbulucu"
cat > "src/main/java/com/example/irbulucu/MainActivity.kt" <<'__IR_EOF__'
package com.example.irbulucu

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.hardware.ConsumerIrManager
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Spinner
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private var ir: ConsumerIrManager? = null
    private val store by lazy { RemoteStore(this) }

    // --- Sayfalar ve sekmeler ---
    private lateinit var scanPage: ScrollView
    private lateinit var savedPage: ScrollView
    private lateinit var tabScan: TextView
    private lateinit var tabSaved: TextView
    private lateinit var savedBox: LinearLayout

    // --- Kumanda arama sayfası ---
    private lateinit var cbProtos: Map<Proto, CheckBox>
    private lateinit var rbFull: RadioButton
    private lateinit var seekDelay: SeekBar
    private lateinit var tvDelay: TextView
    private lateinit var btnScan: Button
    private lateinit var btnLit: Button
    private lateinit var tvProgress: TextView
    private lateinit var progress: ProgressBar
    private lateinit var verifyBox: LinearLayout
    private lateinit var tvVerify: TextView
    private lateinit var etName: EditText
    private lateinit var etKey: EditText
    private lateinit var spKey: Spinner

    // --- Tarama durumu ---
    private var specs: List<CodeSpec> = emptyList()
    private var scanDelay = 600
    @Volatile private var running = false
    @Volatile private var lastSent = -1
    private var verifyIdx = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ir = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager
        buildUi()
        refreshSaved()
    }

    override fun onPause() {
        super.onPause()
        if (running) stopScan()
    }

    // =====================================================================
    //  GENEL ARAYÜZ (iki sayfa + alt sekme çubuğu)
    // =====================================================================
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun label(text: String, size: Float, bold: Boolean = false): TextView {
        val tv = TextView(this)
        tv.text = text
        tv.textSize = size
        if (bold) tv.setTypeface(tv.typeface, Typeface.BOLD)
        tv.setPadding(0, dp(6), 0, dp(6))
        return tv
    }

    private fun buildUi() {
        val outer = LinearLayout(this)
        outer.orientation = LinearLayout.VERTICAL

        val frame = FrameLayout(this)
        scanPage = buildScanPage()
        savedPage = buildSavedPage()
        frame.addView(
            scanPage,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        )
        frame.addView(
            savedPage,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        )
        outer.addView(frame, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        val bar = LinearLayout(this)
        bar.orientation = LinearLayout.HORIZONTAL
        bar.setBackgroundColor(Color.parseColor("#1F1F23"))
        tabScan = tabView("🔍  Kumanda Ara") { selectTab(0) }
        tabSaved = tabView("🎛  Kumandalarım") { selectTab(1) }
        bar.addView(tabScan, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        bar.addView(tabSaved, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        outer.addView(
            bar,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        )

        setContentView(outer)
        selectTab(0)
    }

    private fun tabView(text: String, onClick: () -> Unit): TextView {
        val tv = TextView(this)
        tv.text = text
        tv.textSize = 15f
        tv.setTypeface(tv.typeface, Typeface.BOLD)
        tv.gravity = Gravity.CENTER
        tv.setPadding(dp(8), dp(16), dp(8), dp(16))
        tv.isClickable = true
        tv.setOnClickListener { onClick() }
        return tv
    }

    private fun selectTab(i: Int) {
        scanPage.visibility = if (i == 0) View.VISIBLE else View.GONE
        savedPage.visibility = if (i == 1) View.VISIBLE else View.GONE
        val on = Color.parseColor("#FFB300")
        val off = Color.parseColor("#9E9E9E")
        tabScan.setTextColor(if (i == 0) on else off)
        tabSaved.setTextColor(if (i == 1) on else off)
        if (i == 1) refreshSaved()
    }

    // =====================================================================
    //  SAYFA 1: KUMANDA ARA
    // =====================================================================
    private fun buildScanPage(): ScrollView {
        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(dp(16), dp(16), dp(16), dp(32))

        root.addView(label("Kumanda Ara", 22f, true))
        root.addView(
            label(
                "Telefonun üst kenarındaki IR ledini lambaya doğrultun (1-2 m). " +
                    "Taramayı başlatın; lamba tepki verdiği anda \"LAMBA YANDI\" düğmesine basın. " +
                    "Kaydedince kumanda “Kumandalarım” sayfasına eklenir.",
                14f
            )
        )

        if (ir?.hasIrEmitter() != true) {
            root.addView(label("⚠️ Bu telefonda IR verici bulunamadı. Uygulama çalışmaz.", 15f, true))
        }

        // Protokoller
        root.addView(label("Denenecek protokoller", 16f, true))
        val map = LinkedHashMap<Proto, CheckBox>()
        for (pair in Proto.values().toList().chunked(2)) {
            val row = LinearLayout(this)
            row.orientation = LinearLayout.HORIZONTAL
            for (p in pair) {
                val cb = CheckBox(this)
                cb.text = p.title
                cb.isChecked = (p == Proto.NEC)
                row.addView(
                    cb,
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                )
                map[p] = cb
            }
            root.addView(row)
        }
        cbProtos = map

        // Tarama modu
        val rbFast = RadioButton(this)
        rbFast.text = "Hızlı (yaygın adresler)"
        rbFast.id = View.generateViewId()
        rbFast.isChecked = true
        rbFull = RadioButton(this)
        rbFull.text = "Tam (tüm adresler, çok uzun sürer)"
        rbFull.id = View.generateViewId()
        val rg = RadioGroup(this)
        rg.orientation = LinearLayout.VERTICAL
        rg.addView(rbFast)
        rg.addView(rbFull)
        root.addView(rg)

        // Hız (saniye)
        tvDelay = label(delayText(600), 14f)
        root.addView(tvDelay)
        seekDelay = SeekBar(this)
        seekDelay.max = 28 // 0,2 sn ... 3,0 sn
        seekDelay.progress = 4 // varsayılan 0,6 sn
        seekDelay.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) {
                tvDelay.text = delayText(200 + p * 100)
            }

            override fun onStartTrackingTouch(s: SeekBar?) {}
            override fun onStopTrackingTouch(s: SeekBar?) {}
        })
        root.addView(seekDelay)
        root.addView(
            label(
                "Yavaş tarama, lambanın tepkisini yakalamayı kolaylaştırır. " +
                    "YANDI'ya basınca uygulama birkaç kod geri gider.",
                12f
            )
        )

        // Başlat / Yandı
        btnScan = Button(this)
        btnScan.text = "▶ Taramayı başlat"
        btnScan.isEnabled = ir?.hasIrEmitter() == true
        btnScan.setOnClickListener { if (running) stopScan() else startScan() }
        root.addView(btnScan)

        btnLit = Button(this)
        btnLit.text = "💡 LAMBA YANDI!"
        btnLit.textSize = 20f
        btnLit.isEnabled = false
        btnLit.setOnClickListener { onLit() }
        root.addView(
            btnLit,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(80))
        )

        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        root.addView(progress)
        tvProgress = label("", 13f)
        root.addView(tvProgress)

        // Doğrulama ve kaydetme paneli
        verifyBox = LinearLayout(this)
        verifyBox.orientation = LinearLayout.VERTICAL
        verifyBox.visibility = View.GONE
        verifyBox.setPadding(0, dp(12), 0, dp(12))
        verifyBox.addView(label("Bulunan kodu doğrula", 18f, true))
        tvVerify = label("", 14f)
        verifyBox.addView(tvVerify)

        val nav = LinearLayout(this)
        nav.orientation = LinearLayout.HORIZONTAL
        nav.addView(navBtn("◀ Önceki") { stepVerify(-1) }, navLp())
        nav.addView(navBtn("↻ Gönder") { sendCurrent() }, navLp())
        nav.addView(navBtn("Sonraki ▶") { stepVerify(1) }, navLp())
        verifyBox.addView(nav)

        verifyBox.addView(label("Kaydet", 16f, true))
        etName = EditText(this)
        etName.hint = "Kumanda adı (örn. Salon lambası)"
        etName.setSingleLine()
        verifyBox.addView(etName)

        verifyBox.addView(label("Bulunan kod hangi tuş?", 14f))
        spKey = Spinner(this)
        spKey.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            IrGen.DEFAULT_KEYS.map { IrGen.keyPickerLabel(it) }
        )
        spKey.setSelection(0)
        verifyBox.addView(spKey)

        etKey = EditText(this)
        etKey.hint = "veya özel tuş adı yaz (isteğe bağlı)"
        etKey.setSingleLine()
        verifyBox.addView(etKey)

        verifyBox.addView(navBtn("✅ Bu doğru — kaydet ve kumandayı aç") { saveCurrent() })
        root.addView(verifyBox)

        val sv = ScrollView(this)
        sv.addView(root)
        return sv
    }

    private fun delayText(ms: Int): String =
        "Kodlar arası bekleme: " + "%.1f".format(ms / 1000.0) + " sn"

    private fun navBtn(t: String, action: () -> Unit): Button {
        val b = Button(this)
        b.text = t
        b.setOnClickListener { action() }
        return b
    }

    private fun navLp() =
        LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)

    // =====================================================================
    //  SAYFA 2: KUMANDALARIM
    // =====================================================================
    private fun buildSavedPage(): ScrollView {
        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(dp(16), dp(16), dp(16), dp(32))
        root.addView(label("Kumandalarım", 22f, true))
        root.addView(
            label(
                "Kumandaya dokun: açma-kapama, ışık ve diğer tuşlar. " +
                    "Basılı tut veya ⋮: ad değiştir, bilgi, sil.",
                13f
            )
        )
        savedBox = LinearLayout(this)
        savedBox.orientation = LinearLayout.VERTICAL
        root.addView(savedBox)

        val sv = ScrollView(this)
        sv.addView(root)
        return sv
    }

    private fun refreshSaved() {
        savedBox.removeAllViews()
        val list = store.load()
        if (list.isEmpty()) {
            savedBox.addView(
                label("Henüz kayıtlı kumanda yok. “Kumanda Ara” sayfasından lambanı bul ve kaydet.", 14f)
            )
            return
        }
        for (r in list) {
            val learned = r.keys.count { it.cmd >= 0 }
            val card = RemoteCardView(this)
            card.setInfo(
                r.name,
                r.proto.name + " • adres 0x" + "%02X".format(r.addr) + " • " + learned + " tuş"
            )
            card.setOnClickListener { openPanel(r) }
            card.setOnLongClickListener {
                remoteMenu(r)
                true
            }

            val row = LinearLayout(this)
            row.orientation = LinearLayout.HORIZONTAL
            row.gravity = Gravity.CENTER_VERTICAL
            row.addView(card, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(
                uiPill(this, "⋮", 22f) { remoteMenu(r) },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                )
            )
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            lp.setMargins(0, dp(6), 0, dp(6))
            savedBox.addView(row, lp)
        }
    }

    private fun openPanel(r: Remote) {
        RemotePanel(this, store, r, { freq, pattern -> transmit(freq, pattern) }) {
            refreshSaved()
        }.show()
    }

    private fun remoteMenu(r: Remote) {
        val items = arrayOf("Aç (kumanda paneli)", "Yeniden adlandır", "Bilgi / kodlar", "Sil")
        AlertDialog.Builder(this)
            .setTitle(r.name)
            .setItems(items) { _, which ->
                when (which) {
                    0 -> openPanel(r)
                    1 -> uiAsk(this, "Kumanda adı", r.name) { n ->
                        r.name = n
                        store.upsert(r)
                        refreshSaved()
                    }
                    2 -> uiMessage(this, r.name, remoteInfoText(r))
                    3 -> uiConfirm(this, "“" + r.name + "” kumandası silinsin mi?") {
                        store.delete(r.id)
                        refreshSaved()
                    }
                    else -> {}
                }
            }
            .show()
    }

    // =====================================================================
    //  TARAMA
    // =====================================================================
    private fun startScan() {
        val protos = cbProtos.filter { it.value.isChecked }.keys
        if (protos.isEmpty()) {
            uiToast(this, "En az bir protokol seçin")
            return
        }
        specs = IrGen.generate(protos, rbFull.isChecked)
        scanDelay = 200 + seekDelay.progress * 100
        lastSent = -1
        running = true
        verifyBox.visibility = View.GONE
        progress.max = specs.size
        progress.progress = 0
        val minutes = specs.size.toLong() * (70 + scanDelay) / 60000
        tvProgress.text = "Toplam ${specs.size} kod, tahmini süre ~${minutes + 1} dk"
        updateScanButtons()

        val list = specs
        val delayMs = scanDelay
        Thread {
            var i = 0
            var failed = false
            while (running && i < list.size) {
                val s = list[i]
                val pat = s.pattern()
                if (!transmit(s.proto.freq, pat)) {
                    failed = true
                    break
                }
                lastSent = i
                val idx = i
                runOnUiThread {
                    progress.progress = idx + 1
                    tvProgress.text = "${idx + 1} / ${list.size}\n${s.label()}"
                }
                try {
                    Thread.sleep((pat.sum() / 1000 + delayMs).toLong())
                } catch (e: InterruptedException) {
                    break
                }
                i++
            }
            val finishedAll = i >= list.size
            runOnUiThread {
                if (failed) {
                    uiToast(this, "IR gönderilemedi. Frekans bu telefonda desteklenmiyor olabilir.")
                } else if (finishedAll && running) {
                    uiToast(this, "Tarama bitti, lamba tepki vermedi.")
                }
                running = false
                updateScanButtons()
            }
        }.start()
    }

    private fun stopScan() {
        running = false
        updateScanButtons()
    }

    private fun updateScanButtons() {
        btnScan.text = if (running) "⏹ Taramayı durdur" else "▶ Taramayı başlat"
        btnLit.isEnabled = running
        if (running) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    /** Kullanıcı lamba yandı dedi: tepki gecikmesi kadar geriye gidip kodları tek tek denetle. */
    private fun onLit() {
        if (lastSent < 0) {
            uiToast(this, "Henüz kod gönderilmedi")
            return
        }
        stopScan()
        val back = 1600 / (scanDelay + 70) + 2 // ~1,6 sn tepki süresi
        verifyIdx = maxOf(0, lastSent - back)
        verifyBox.visibility = View.VISIBLE
        showVerify()
    }

    // =====================================================================
    //  DOĞRULAMA VE KAYDETME
    // =====================================================================
    private fun showVerify() {
        val s = specs[verifyIdx]
        tvVerify.text = "Kod ${verifyIdx + 1} / ${specs.size}\n\n" +
            IrGen.describe(s.proto, s.addr, s.cmd) + "\n\n" +
            "◀ / ▶ ile diğer kodları deneyin (her basışta kod gönderilir). " +
            "Lamba tepki veren kodda aşağıdan kaydedin."
    }

    private fun stepVerify(d: Int) {
        if (specs.isEmpty()) return
        verifyIdx = (verifyIdx + d).coerceIn(0, specs.size - 1)
        showVerify()
        sendCurrent()
    }

    private fun sendCurrent() {
        val s = specs.getOrNull(verifyIdx) ?: return
        if (!transmit(s.proto.freq, s.pattern())) uiToast(this, "Gönderilemedi")
    }

    private fun saveCurrent() {
        val s = specs.getOrNull(verifyIdx) ?: return
        val typedName = etName.text.toString().trim()
        val name = if (typedName.isEmpty()) "Lamba" else typedName
        val typedKey = etKey.text.toString().trim()
        val keyName = if (typedKey.isNotEmpty()) {
            typedKey
        } else {
            IrGen.DEFAULT_KEYS[spKey.selectedItemPosition.coerceIn(0, IrGen.DEFAULT_KEYS.size - 1)]
        }

        // Aynı protokol + adres zaten kayıtlıysa yeni kumanda açma, tuşu ona ekle
        val existing = store.load().firstOrNull { it.proto == s.proto && it.addr == s.addr }
        val remote: Remote
        if (existing != null) {
            remote = existing
            val k = remote.key(keyName)
            if (k != null) {
                k.cmd = s.cmd
            } else {
                remote.keys.add(Key(keyName, s.cmd))
            }
            remote.lastPos = s.cmd
            if (typedName.isNotEmpty()) remote.name = typedName
            uiToast(this, "Mevcut kumandaya eklendi: " + IrGen.keyPickerLabel(keyName))
        } else {
            remote = Remote.create(name, s.proto, s.addr, s.cmd, keyName, System.currentTimeMillis())
            uiToast(this, "Kumanda kaydedildi: " + name)
        }
        store.upsert(remote)

        etName.setText("")
        etKey.setText("")
        verifyBox.visibility = View.GONE
        selectTab(1)
        openPanel(remote)
    }

    // =====================================================================
    //  IR GÖNDERİMİ
    // =====================================================================
    private fun transmit(freq: Int, pattern: IntArray): Boolean {
        val m = ir ?: return false
        return try {
            m.transmit(freq, pattern)
            true
        } catch (e: Exception) {
            false
        }
    }
}
__IR_EOF__
base64 -d > irbulucu.jks <<'__IR_B64__'
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
__IR_B64__
echo "Proje dosyalari olusturuldu."
