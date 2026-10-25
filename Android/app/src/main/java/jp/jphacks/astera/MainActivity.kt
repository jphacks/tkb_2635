package jp.jphacks.astera

import android.Manifest
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.webkit.*
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.webkit.WebViewAssetLoader
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/** Androidの権限とライフサイクルだけを担当。計算・3D・画面は同梱コードから実行する。 */
class MainActivity : ComponentActivity() {
    private lateinit var web: WebView
    private lateinit var orientation: OrientationBridge
    private var cameraRequest: PermissionRequest? = null
    private var geoRequest: Pair<String, GeolocationPermissions.Callback>? = null
    private val cameraPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        cameraRequest?.let { if (granted) it.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) else it.deny() }
        cameraRequest = null
    }
    private val locationPermission = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        geoRequest?.let { (origin, callback) -> callback.invoke(origin, result.values.any { it }, false) }
        geoRequest = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        web = WebView(this)
        setContentView(web)
        ViewCompat.setOnApplyWindowInsetsListener(web) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        orientation = OrientationBridge(this, web)
        val loader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this)).build()
        web.setBackgroundColor(0xff050c17.toInt())
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            setGeolocationEnabled(true)
            userAgentString = "$userAgentString Astera/0.1 (Android)"
        }
        WebView.setWebContentsDebuggingEnabled(applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0)
        web.addJavascriptInterface(orientation, "AsteraDevice")
        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                loader.shouldInterceptRequest(request.url)

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                if (uri.scheme == "https" && uri.host == HOST) return false
                if (uri.scheme == "https" && request.isForMainFrame) {
                    runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                }
                return true
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                runOnUiThread {
                    if (!trusted(request.origin) || !request.resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) {
                        request.deny(); return@runOnUiThread
                    }
                    cameraRequest?.deny()
                    if (allowed(Manifest.permission.CAMERA)) request.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE))
                    else { cameraRequest = request; cameraPermission.launch(Manifest.permission.CAMERA) }
                }
            }
            override fun onPermissionRequestCanceled(request: PermissionRequest) {
                if (cameraRequest === request) cameraRequest = null
            }
            override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
                if (!trusted(Uri.parse(origin))) { callback.invoke(origin, false, false); return }
                if (allowed(Manifest.permission.ACCESS_COARSE_LOCATION) || allowed(Manifest.permission.ACCESS_FINE_LOCATION)) {
                    callback.invoke(origin, true, false)
                } else {
                    geoRequest?.let { it.second.invoke(it.first, false, false) }
                    geoRequest = origin to callback
                    locationPermission.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
                }
            }
            override fun onGeolocationPermissionsHidePrompt() { geoRequest = null }
        }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                web.evaluateJavascript("window.Astera?.back?.() === true") { consumed -> if (consumed != "true") finish() }
            }
        })
        web.loadUrl("https://$HOST/assets/web/index.html")
    }

    private fun trusted(uri: Uri) = uri.scheme == "https" && uri.host == HOST
    private fun allowed(permission: String) = ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
    override fun onPause() {
        web.evaluateJavascript("window.Astera?.suspend?.()", null)
        orientation.stop()
        web.onPause()
        super.onPause()
    }
    override fun onResume() { super.onResume(); if (::web.isInitialized) web.onResume() }
    override fun onDestroy() {
        cameraRequest?.deny()
        geoRequest?.let { it.second.invoke(it.first, false, false) }
        orientation.stop()
        web.removeJavascriptInterface("AsteraDevice")
        web.destroy()
        super.onDestroy()
    }
    companion object { const val HOST = "appassets.androidplatform.net" }
}
