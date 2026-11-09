package com.picacomic_miuix

import android.os.Build
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.result.contract.ActivityResultContracts
import android.os.Environment
import android.Manifest
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import java.io.File
import android.os.Bundle
import com.google.android.gms.common.GoogleApiAvailability

class MainActivity: FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 沉浸式：内容绘制到状态栏 / 导航栏之下，由 Flutter 侧按 MediaQuery.padding 自行避让。
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    var volumeListen = VolumeListen()
    var listening = false

    private var storagePermissionResult: MethodChannel.Result? = null
    private val STORAGE_PERMISSION_REQ = 9911
    private var pickDirectoryResult: MethodChannel.Result? = null
    private val pickDirectoryLauncher =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            handlePickedDirectory(uri)
        }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        val channel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.picacomic_miuix/volume")
        channel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    listening = true
                    volumeListen.whenUp = {
                        events.success(1)
                    }
                    volumeListen.whenDown = {
                        events.success(2)
                    }
                }
                override fun onCancel(arguments: Any?) {
                    listening = false
                }
        })
        //拦截屏幕截图
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"com.picacomic_miuix/screenshot").setMethodCallHandler{
                _, _ ->
            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"com.picacomic_miuix/secure").setMethodCallHandler{
                _, _ ->
            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        }
        //获取cpu架构
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"com.picacomic_miuix/device").setMethodCallHandler{
                _, res ->
            res.success(getDeviceInfo())
        }
        //获取http代理
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"com.picacomic_miuix/proxy").setMethodCallHandler{
                _, res ->
            res.success(getProxy())
        }
        //保持屏幕常亮
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"com.picacomic_miuix/keepScreenOn").setMethodCallHandler{
                call, _ ->
            if(call.method == "set")
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }

        //应用内更新: 调起系统安装器
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"com.picacomic_miuix/installer").setMethodCallHandler{
                call, res ->
            when (call.method) {
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null || !File(path).exists()) {
                        res.error("not_found", "安装包不存在", null)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        res.error("need_permission", "need_permission", null)
                    } else {
                        try {
                            val uri = FileProvider.getUriForFile(this, "$packageName.update_provider", File(path))
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            res.success("ok")
                        } catch (e: Exception) {
                            res.error("install", e.message, null)
                        }
                    }
                }
                "permission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")))
                        }
                        res.success(null)
                    } catch (e: Exception) {
                        res.error("permission", e.message, null)
                    }
                }
                else -> res.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"pica_comic/playServer").setMethodCallHandler{
                _, res ->
            val flag = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this) == com.google.android.gms.common.ConnectionResult.SUCCESS
            res.success(flag)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"pica_comic/settings").setMethodCallHandler{
                call, res ->
            if(call.method == "link") {
                try {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        Intent(
                            android.provider.Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS,
                            Uri.parse("package:com.picacomic_miuix"),
                        )
                    } else {
                        Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:com.picacomic_miuix")
                        }
                    }
                    startActivity(intent)
                    res.success(null)
                } catch (e: Exception) {
                    try {
                        val fallback = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:com.picacomic_miuix")
                        }
                        startActivity(fallback)
                        res.success(null)
                    } catch (e2: Exception) {
                        res.error("link", e2.message, null)
                    }
                }
            } else if(call.method == "files") {
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                } else {
                    Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                }
                intent.data = Uri.parse("package:com.picacomic_miuix")
                startActivity(intent)
                res.success(null)
            } else if(call.method == "files_check") {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    res.success(Environment.isExternalStorageManager())
                } else {
                    res.success(
                        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
                            && ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED)
                }
            } else if (call.method == "request_storage") {
                // Gallery save on API < 29 writes public Pictures/ and needs WRITE_EXTERNAL_STORAGE.
                // API 29+ uses MediaStore scoped inserts — no runtime write permission.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    res.success(true)
                } else {
                    val writeGranted = ContextCompat.checkSelfPermission(
                        this, Manifest.permission.WRITE_EXTERNAL_STORAGE
                    ) == PackageManager.PERMISSION_GRANTED
                    if (writeGranted) {
                        res.success(true)
                    } else if (storagePermissionResult != null) {
                        res.error("busy", "permission request already in flight", null)
                    } else {
                        storagePermissionResult = res
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                Manifest.permission.WRITE_EXTERNAL_STORAGE,
                                Manifest.permission.READ_EXTERNAL_STORAGE,
                            ),
                            STORAGE_PERMISSION_REQ,
                        )
                    }
                }
            } else if (call.method == "pick_directory") {
                if (pickDirectoryResult != null) {
                    res.error("busy", "directory picker already in flight", null)
                } else {
                    pickDirectoryResult = res
                    try {
                        pickDirectoryLauncher.launch(null)
                    } catch (e: Exception) {
                        pickDirectoryResult = null
                        res.error("pick_directory", e.message, null)
                    }
                }
            } else if (call.method == "sdk_int") {
                res.success(Build.VERSION.SDK_INT)
            }

        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if(listening){
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    volumeListen.down()
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    volumeListen.up()
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_PERMISSION_REQ) {
            val ok = grantResults.isNotEmpty() &&
                grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            storagePermissionResult?.success(ok)
            storagePermissionResult = null
        }
    }

    private fun handlePickedDirectory(uri: Uri?) {
        val pending = pickDirectoryResult
        pickDirectoryResult = null
        if (pending == null) return
        if (uri == null) {
            pending.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: SecurityException) {
        } catch (_: Exception) {
        }
        val path = pathFromTreeUri(uri)
        val displayName = displayNameFromTreeUri(uri)
        pending.success(
            hashMapOf(
                "uri" to uri.toString(),
                "path" to path,
                "displayName" to displayName,
            )
        )
    }

    private fun pathFromTreeUri(treeUri: Uri): String? {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val split = docId.split(":", limit = 2)
            if (split.size < 2) return null
            if (split[0] != "primary") return null
            val relative = split[1]
            File(Environment.getExternalStorageDirectory(), relative).absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun displayNameFromTreeUri(treeUri: Uri): String {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val relative = if (docId.contains(":")) docId.substringAfter(":") else docId
            if (relative.isBlank()) "storage" else relative
        } catch (_: Exception) {
            "storage"
        }
    }

    private fun getDeviceInfo(): String{
        //获取cpu架构从而找到应当下载的app版本
        return Build.SUPPORTED_ABIS[0]
    }

    private fun getProxy(): String{
        val host = System.getProperty("http.proxyHost")
        val port = System.getProperty("http.proxyPort")
        return if(host!=null&&port!=null){
            "$host:$port"
        }else{
            "No Proxy"
        }
    }
}

class VolumeListen{
    var whenUp = fun() {}
    var whenDown = fun() {}
    fun up(){
        whenUp()
    }
    fun down(){
        whenDown()
    }
}
