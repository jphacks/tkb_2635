package jp.jphacks.astera

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.GeomagneticField
import android.media.AudioManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import org.json.JSONObject

/** 北基準の回転ベクトルから、背面カメラの前方向と画面の上方向を送る。角度3つの合成はしない。 */
class OrientationBridge(private val context: Context, private val web: WebView) : SensorEventListener {
    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val sensor = manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private var tracking = false
    private var lastSent = 0L

    @JavascriptInterface fun available() = sensor != null
    @JavascriptInterface fun soundAllowed() =
        (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager).ringerMode == AudioManager.RINGER_MODE_NORMAL
    @JavascriptInterface fun declination(lat: Double, lon: Double, height: Double, time: Long): Double =
        GeomagneticField(lat.toFloat(), lon.toFloat(), height.toFloat(), time).declination.toDouble()
    @JavascriptInterface fun setTracking(enabled: Boolean) {
        web.post {
            stop()
            if (enabled && sensor != null) {
                tracking = manager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
            }
        }
    }
    fun stop() { tracking = false; manager.unregisterListener(this) }

    override fun onSensorChanged(event: SensorEvent) {
        if (!tracking || event.timestamp - lastSent < 32_000_000L) return
        lastSent = event.timestamp
        val matrix = FloatArray(9)
        SensorManager.getRotationMatrixFromVector(matrix, event.values)
        // 端末は縦向き。世界座標は east / magnetic north / up。
        val value = JSONObject().apply {
            put("forward", org.json.JSONArray(listOf(-matrix[2], -matrix[5], -matrix[8])))
            put("up", org.json.JSONArray(listOf(matrix[1], matrix[4], matrix[7])))
            put("accuracy", event.accuracy)
        }
        web.post {
            if (tracking) web.evaluateJavascript("window.dispatchEvent(new CustomEvent('astera-orientation',{detail:$value}))", null)
        }
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
