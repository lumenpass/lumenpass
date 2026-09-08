package com.tranit.lumenpass.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageView
import android.widget.Toast
import com.tranit.lumenpass.android.autofill.AutofillBridgePlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val screenshotChannel = "com.tranit.lumenpass/screenshot"
    private val nativeBannerChannel = "com.tranit.lumenpass/native_banner"
    private val runtimeInfoChannel = "app.runtime.info"

    private var privacyBlurView: ImageView? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AutofillBridgePlugin())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, runtimeInfoChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInfo" -> {
                    val packageInfo = packageManager.getPackageInfo(packageName, 0)
                    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        packageInfo.longVersionCode.toString()
                    } else {
                        @Suppress("DEPRECATION")
                        packageInfo.versionCode.toString()
                    }
                    result.success(
                        mapOf(
                            "bundleIdentifier" to packageName,
                            "version" to (packageInfo.versionName ?: ""),
                            "buildNumber" to versionCode,
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenshotChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "setFlagSecure" -> {
                    val block = call.argument<Boolean>("block") ?: false
                    if (block) {
                        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativeBannerChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val message = call.argument<String>("message")
                    if (message.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    showNativeBanner(message)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun showNativeBanner(message: String) {
        runOnUiThread {
            val toast = Toast.makeText(applicationContext, message, Toast.LENGTH_LONG)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                toast.setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL, 0, 180)
            }
            toast.show()
        }
    }

    // ── App Switcher Privacy Cover ─────────────────────────────────────────
    //
    // Android captures a thumbnail of the current activity when the user
    // opens the recents / app switcher. To prevent sensitive vault contents
    // from showing up in that snapshot, we install a blurred overlay over
    // the decor view while the activity is not in the foreground, then
    // remove it on resume.

    override fun onPause() {
        super.onPause()
        showPrivacyBlur()
    }

    override fun onResume() {
        super.onResume()
        hidePrivacyBlur()
    }

    private fun showPrivacyBlur() {
        if (privacyBlurView != null) return
        val decor = window.decorView as? ViewGroup ?: return
        val blurred = captureBlurredSnapshot(decor) ?: return

        val overlay = ImageView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            scaleType = ImageView.ScaleType.FIT_XY
            setImageBitmap(blurred)
        }
        decor.addView(overlay)
        overlay.bringToFront()
        privacyBlurView = overlay
    }

    private fun hidePrivacyBlur() {
        privacyBlurView?.let { view ->
            (view.parent as? ViewGroup)?.removeView(view)
            (view.drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap?.recycle()
        }
        privacyBlurView = null
    }

    /**
     * Draws [view] into a bitmap and applies a cheap downscale/upscale blur.
     * Returns null if the view has no measured size or drawing fails
     * (e.g. a SurfaceView such as the camera scanner is on screen).
     */
    private fun captureBlurredSnapshot(view: View): Bitmap? {
        val width = view.width
        val height = view.height
        if (width <= 0 || height <= 0) return null

        return try {
            val source = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(source)
            view.draw(canvas)

            val scale = 0.08f
            val smallW = (width * scale).toInt().coerceAtLeast(1)
            val smallH = (height * scale).toInt().coerceAtLeast(1)
            val small = Bitmap.createScaledBitmap(source, smallW, smallH, true)
            source.recycle()

            val blurred = Bitmap.createScaledBitmap(small, width, height, true)
            if (blurred !== small) small.recycle()
            blurred
        } catch (_: Throwable) {
            null
        }
    }
}
