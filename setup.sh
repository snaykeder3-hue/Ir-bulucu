#!/usr/bin/env bash
# IR Lamba Bulucu - proje dosyalarini olusturur (GitHub Actions bu dosyayi calistirir)
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
        versionCode = 1
        versionName = "1.0"
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
cat > "src/main/java/com/example/irbulucu/MainActivity.kt" <<'__IR_EOF__'
package com.example.irbulucu

import android.content.Context
import android.graphics.Typeface
import android.hardware.ConsumerIrManager
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : AppCompatActivity() {

    private var ir: ConsumerIrManager? = null
    private val prefs by lazy { getSharedPreferences("ir_codes", Context.MODE_PRIVATE) }

    // --- Arayüz ---
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
    private lateinit var savedBox: LinearLayout

    // --- Tarama durumu ---
    private var specs: List<CodeSpec> = emptyList()
    private var scanDelay = 150
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
    //  ARAYÜZ
    // =====================================================================
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun label(text: String, size: Float, bold: Boolean = false) = TextView(this).apply {
        this.text = text
        textSize = size
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setPadding(0, dp(6), 0, dp(6))
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(32))
        }
        setContentView(ScrollView(this).apply { addView(root) })

        root.addView(label("IR Lamba Bulucu", 22f, true))
        root.addView(
            label(
                "Telefonun üst kenarındaki IR ledini lambaya doğrultun (1-2 m). " +
                    "Taramayı başlatın; lamba tepki verdiği anda \"LAMBA YANDI\" düğmesine basın.",
                14f
            )
        )

        if (ir?.hasIrEmitter() != true) {
            root.addView(label("⚠️ Bu telefonda IR verici bulunamadı. Uygulama çalışmaz.", 15f, true))
        }

        // Protokoller
        root.addView(label("Denenecek protokoller", 16f, true))
        val map = LinkedHashMap<Proto, CheckBox>()
        Proto.values().toList().chunked(2).forEach { pair ->
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            pair.forEach { p ->
                val cb = CheckBox(this).apply {
                    text = p.title
                    isChecked = (p == Proto.NEC)
                }
                row.addView(cb, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                map[p] = cb
            }
            root.addView(row)
        }
        cbProtos = map

        // Tarama modu
        val rbFast = RadioButton(this).apply {
            text = "Hızlı (yaygın adresler)"
            id = View.generateViewId()
            isChecked = true
        }
        rbFull = RadioButton(this).apply {
            text = "Tam (tüm adresler, çok uzun sürer)"
            id = View.generateViewId()
        }
        root.addView(RadioGroup(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(rbFast)
            addView(rbFull)
        })

        // Hız
        tvDelay = label("Kodlar arası bekleme: 150 ms", 14f)
        root.addView(tvDelay)
        seekDelay = SeekBar(this).apply {
            max = 450
            progress = 100
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) {
                    tvDelay.text = "Kodlar arası bekleme: ${p + 50} ms"
                }
                override fun onStartTrackingTouch(s: SeekBar?) {}
                override fun onStopTrackingTouch(s: SeekBar?) {}
            })
        }
        root.addView(seekDelay)

        // Başlat / Yandı
        btnScan = Button(this).apply {
            text = "▶ Taramayı başlat"
            isEnabled = ir?.hasIrEmitter() == true
            setOnClickListener { if (running) stopScan() else startScan() }
        }
        root.addView(btnScan)

        btnLit = Button(this).apply {
            text = "💡 LAMBA YANDI!"
            textSize = 20f
            isEnabled = false
            setOnClickListener { onLit() }
        }
        root.addView(btnLit, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(80)
        ))

        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        root.addView(progress)
        tvProgress = label("", 13f)
        root.addView(tvProgress)

        // Doğrulama paneli
        verifyBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(0, dp(12), 0, dp(12))
        }
        verifyBox.addView(label("Kodu doğrula", 18f, true))
        tvVerify = label("", 14f)
        verifyBox.addView(tvVerify)

        fun navBtn(t: String, action: () -> Unit) = Button(this).apply {
            text = t
            setOnClickListener { action() }
        }
        val nav = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val lp = { LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f) }
        nav.addView(navBtn("◀ Önceki") { stepVerify(-1) }, lp())
        nav.addView(navBtn("↻ Gönder") { sendCurrent() }, lp())
        nav.addView(navBtn("Sonraki ▶") { stepVerify(1) }, lp())
        verifyBox.addView(nav)

        etName = EditText(this).apply {
            hint = "Ad (örn. Lamba AÇ/KAPAT)"
            setSingleLine()
        }
        verifyBox.addView(etName)
        verifyBox.addView(navBtn("✅ Bu doğru — kaydet") { saveCurrent() })
        root.addView(verifyBox)

        // Kayıtlı kodlar
        root.addView(label("Kayıtlı kodlar", 18f, true))
        savedBox = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(savedBox)
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    // =====================================================================
    //  TARAMA
    // =====================================================================
    private fun startScan() {
        val protos = cbProtos.filter { it.value.isChecked }.keys
        if (protos.isEmpty()) {
            toast("En az bir protokol seçin")
            return
        }
        specs = IrGen.generate(protos, rbFull.isChecked)
        scanDelay = seekDelay.progress + 50
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
                if (!transmit(s.proto.freq, pat)) { failed = true; break }
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
                if (failed) toast("IR gönderilemedi. Frekans bu telefonda desteklenmiyor olabilir.")
                else if (finishedAll && running) toast("Tarama bitti, lamba tepki vermedi.")
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
        if (running) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    /** Kullanıcı lamba yandı dedi: tepki gecikmesi kadar geriye gidip kodları tek tek denetle. */
    private fun onLit() {
        if (lastSent < 0) {
            toast("Henüz kod gönderilmedi")
            return
        }
        stopScan()
        val back = 1500 / (scanDelay + 70) + 2 // ~1,5 sn tepki süresi
        verifyIdx = maxOf(0, lastSent - back)
        verifyBox.visibility = View.VISIBLE
        showVerify()
    }

    // =====================================================================
    //  DOĞRULAMA
    // =====================================================================
    private fun showVerify() {
        val s = specs[verifyIdx]
        tvVerify.text = "Kod ${verifyIdx + 1} / ${specs.size}\n${s.label()}\n\n" +
            "Lamba bu kodda tepki verdiyse kaydedin. Vermediyse ◀ / ▶ ile diğer kodları deneyin " +
            "(her basışta kod gönderilir)."
    }

    private fun stepVerify(d: Int) {
        if (specs.isEmpty()) return
        verifyIdx = (verifyIdx + d).coerceIn(0, specs.size - 1)
        showVerify()
        sendCurrent()
    }

    private fun sendCurrent() {
        val s = specs.getOrNull(verifyIdx) ?: return
        if (!transmit(s.proto.freq, s.pattern())) toast("Gönderilemedi")
    }

    private fun saveCurrent() {
        val s = specs.getOrNull(verifyIdx) ?: return
        val name = etName.text.toString().trim().ifEmpty { "Lamba" }
        val arr = JSONArray()
        s.pattern().forEach { arr.put(it) }
        val o = JSONObject()
            .put("name", name)
            .put("freq", s.proto.freq)
            .put("label", s.label())
            .put("pattern", arr)
        val list = loadSaved()
        list.add(o)
        saveAll(list)
        etName.setText("")
        verifyBox.visibility = View.GONE
        refreshSaved()
        toast("Kaydedildi: $name")
    }

    // =====================================================================
    //  KAYITLI KODLAR
    // =====================================================================
    private fun loadSaved(): MutableList<JSONObject> {
        val arr = JSONArray(prefs.getString("list", "[]"))
        return MutableList(arr.length()) { arr.getJSONObject(it) }
    }

    private fun saveAll(list: List<JSONObject>) {
        val arr = JSONArray()
        list.forEach { arr.put(it) }
        prefs.edit().putString("list", arr.toString()).apply()
    }

    private fun refreshSaved() {
        savedBox.removeAllViews()
        val list = loadSaved()
        if (list.isEmpty()) {
            savedBox.addView(label("Henüz kayıtlı kod yok.", 14f))
            return
        }
        list.forEachIndexed { idx, o ->
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            val send = Button(this).apply {
                text = "▶ ${o.getString("name")}"
                setOnClickListener { sendSaved(o) }
            }
            val del = Button(this).apply {
                text = "🗑"
                setOnClickListener {
                    val l = loadSaved()
                    if (idx < l.size) l.removeAt(idx)
                    saveAll(l)
                    refreshSaved()
                }
            }
            row.addView(send, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(del, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ))
            savedBox.addView(row)
        }
    }

    private fun sendSaved(o: JSONObject) {
        val a = o.getJSONArray("pattern")
        val pat = IntArray(a.length()) { a.getInt(it) }
        if (!transmit(o.getInt("freq"), pat)) toast("Gönderilemedi")
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

/** Desteklenen IR protokolleri ve taşıyıcı frekansları (Hz). */
enum class Proto(val title: String, val freq: Int) {
    NEC("NEC (LED/ucuz lamba)", 38000),
    SAMSUNG("Samsung", 38000),
    SONY("Sony SIRC", 40000),
    RC5("Philips RC5", 36000)
}

/** Tek bir denenecek kod. Pattern ihtiyaç olunca üretilir (hafıza tasarrufu). */
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
echo "Proje dosyalari olusturuldu."
