#!/usr/bin/env bash
# IR Lamba Bulucu v4 - proje dosyalarini (simge dahil) olusturur; GitHub Actions bu dosyayi calistirir
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
        versionCode = 4
        versionName = "3.1"
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
        android:icon="@mipmap/ic_launcher"
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
mkdir -p "src/main/res/mipmap-anydpi-v26"
cat > "src/main/res/mipmap-anydpi-v26/ic_launcher.xml" <<'__IR_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/white" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
__IR_EOF__
mkdir -p "src/main/res/drawable-nodpi"
base64 -d > "src/main/res/drawable-nodpi/ic_launcher_foreground.png" <<'__IR_B64__'
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
__IR_B64__
mkdir -p "src/main/res/mipmap-mdpi"
base64 -d > "src/main/res/mipmap-mdpi/ic_launcher.png" <<'__IR_B64__'
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
__IR_B64__
mkdir -p "src/main/res/mipmap-hdpi"
base64 -d > "src/main/res/mipmap-hdpi/ic_launcher.png" <<'__IR_B64__'
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
BaEIUzwfEcJyAAAAAElFTkSuQmCC
__IR_B64__
mkdir -p "src/main/res/mipmap-xhdpi"
base64 -d > "src/main/res/mipmap-xhdpi/ic_launcher.png" <<'__IR_B64__'
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
SUVORK5CYII=
__IR_B64__
mkdir -p "src/main/res/mipmap-xxhdpi"
base64 -d > "src/main/res/mipmap-xxhdpi/ic_launcher.png" <<'__IR_B64__'
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
PgAAAABJRU5ErkJggg==
__IR_B64__
mkdir -p "src/main/res/mipmap-xxxhdpi"
base64 -d > "src/main/res/mipmap-xxxhdpi/ic_launcher.png" <<'__IR_B64__'
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
__IR_B64__
mkdir -p "."
base64 -d > "irbulucu.jks" <<'__IR_B64__'
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
__IR_B64__
echo "Proje dosyalari olusturuldu."
