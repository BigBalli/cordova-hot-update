package com.cordova.hotupdate;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * Update Manager - Handles checking, downloading, and applying updates
 */
public class UpdateManager {

    private static final String TAG = "UpdateManager";
    private static final int CONNECT_TIMEOUT = 15000;
    private static final int READ_TIMEOUT = 15000;

    private Context context;
    private SharedPreferences prefs;
    private String appId;
    private String apiKey;
    private String baseUrl;

    public UpdateManager(Context context, SharedPreferences prefs) {
        this.context = context;
        this.prefs = prefs;
    }

    public void setCredentials(String appId, String apiKey, String baseUrl) {
        this.appId = appId;
        this.apiKey = apiKey;
        this.baseUrl = baseUrl;
    }

    /**
     * Get native app version from AndroidManifest.xml
     */
    private String getNativeAppVersion() {
        try {
            return context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), 0)
                    .versionName;
        } catch (Exception e) {
            Log.w(TAG, "Could not get app version", e);
            return "unknown";
        }
    }

    /**
     * Check if a new update is available
     */
    public JSONObject checkForUpdate() throws Exception {
        String nativeAppVersion = getNativeAppVersion();
        String manifestUrl = baseUrl + "/api/manifest?appId=" + appId + "&nativeAppVersion=" + nativeAppVersion;

        Log.d(TAG, "Checking for update: " + manifestUrl + " (app version: " + nativeAppVersion + ")");

        HttpURLConnection connection = null;
        try {
            URL url = new URL(manifestUrl);
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("GET");
            connection.setRequestProperty("X-API-Key", apiKey);
            connection.setConnectTimeout(CONNECT_TIMEOUT);
            connection.setReadTimeout(READ_TIMEOUT);

            int responseCode = connection.getResponseCode();
            if (responseCode == HttpURLConnection.HTTP_OK) {
                String response = readStream(connection.getInputStream());
                JSONObject manifest = new JSONObject(response);

                // Save manifest for later use
                prefs.edit().putString("latestManifest", response).apply();
                prefs.edit().putLong("lastCheckTime", System.currentTimeMillis()).apply();

                // Send metrics
                sendMetrics("check", currentVersion);

                return manifest;

            } else if (responseCode == 429) {
                throw new Exception("Rate limit exceeded");
            } else {
                String error = readStream(connection.getErrorStream());
                throw new Exception("Server error: " + error);
            }

        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    /**
     * Download and apply the latest update
     */
    public boolean downloadAndApplyUpdate() throws Exception {
        String manifestJson = prefs.getString("latestManifest", null);
        if (manifestJson == null) {
            throw new Exception("No update available. Call checkForUpdate first.");
        }

        JSONObject manifest = new JSONObject(manifestJson);
        if (!manifest.optBoolean("available", false)) {
            return false;
        }

        String hotfixVersion = manifest.getString("hotfixVersion");
        String nativeAppVersion = manifest.getString("nativeAppVersion");
        String downloadUrl = manifest.getString("url");
        String expectedHash = manifest.getString("hash");
        String signature = manifest.getString("signature");

        Log.d(TAG, "Downloading hotfix version: " + hotfixVersion + " for app version: " + nativeAppVersion);

        // Download the bundle
        byte[] bundle = downloadBundle(downloadUrl);

        // Verify hash
        String actualHash = sha256(bundle);
        if (!actualHash.equals(expectedHash)) {
            Log.e(TAG, "Hash mismatch! Expected: " + expectedHash + ", Got: " + actualHash);
            throw new Exception("Update verification failed: hash mismatch");
        }

        // Verify signature
        if (!Ed25519.verify(bundle, signature)) {
            Log.e(TAG, "Signature verification failed!");
            throw new Exception("Update verification failed: invalid signature");
        }

        // Inject global variable before the hotfix code
        String globalVarInjection = "window.CordovaHotUpdateCurrentAppVersion = \"" + nativeAppVersion + "\";\n\n";
        byte[] injectionBytes = globalVarInjection.getBytes("UTF-8");

        // Combine injection + hotfix code
        byte[] finalBundle = new byte[injectionBytes.length + bundle.length];
        System.arraycopy(injectionBytes, 0, finalBundle, 0, injectionBytes.length);
        System.arraycopy(bundle, 0, finalBundle, injectionBytes.length, bundle.length);

        // Save the bundle with injection (always overwrites - only one hotfix file)
        File updateDir = new File(context.getFilesDir(), "hot-updates");
        if (!updateDir.exists()) {
            updateDir.mkdirs();
        }

        File updateFile = new File(updateDir, "hotfix.js");
        try (FileOutputStream fos = new FileOutputStream(updateFile)) {
            fos.write(finalBundle);
        }

        // Store file path and metadata
        prefs.edit().putString("hotfixVersion", hotfixVersion).apply(); // Just for display
        prefs.edit().putString("updateFilePath", updateFile.getAbsolutePath()).apply();
        prefs.edit().putLong("lastDownloadTime", System.currentTimeMillis()).apply();

        // Send metrics
        sendMetrics("download", hotfixVersion);

        Log.d(TAG, "Hotfix applied: " + hotfixVersion + " (app version: " + nativeAppVersion + ")");

        return true;
    }

    /**
     * Download bundle from URL
     */
    private byte[] downloadBundle(String urlString) throws Exception {
        HttpURLConnection connection = null;
        try {
            URL url = new URL(urlString);
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("GET");
            connection.setRequestProperty("X-API-Key", apiKey);
            connection.setConnectTimeout(CONNECT_TIMEOUT);
            connection.setReadTimeout(READ_TIMEOUT);

            int responseCode = connection.getResponseCode();
            if (responseCode == HttpURLConnection.HTTP_OK) {
                return readBinaryStream(connection.getInputStream());
            } else {
                throw new Exception("Failed to download bundle: HTTP " + responseCode);
            }

        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    /**
     * Send metrics to backend
     */
    public void sendMetrics(String action, String version) {
        try {
            JSONObject metrics = new JSONObject();
            metrics.put("appId", appId);
            metrics.put("action", action);
            metrics.put("version", version);
            metrics.put("timestamp", System.currentTimeMillis());
            metrics.put("platform", "android");

            String metricsUrl = baseUrl + "/api/metrics";
            sendPostRequest(metricsUrl, metrics.toString());

        } catch (Exception e) {
            Log.w(TAG, "Failed to send metrics", e);
            // Don't throw - metrics are optional
        }
    }

    /**
     * Report an error to backend
     */
    public void reportError(String message, String stack) {
        try {
            JSONObject error = new JSONObject();
            error.put("appId", appId);
            error.put("message", message);
            error.put("stack", stack);
            error.put("timestamp", System.currentTimeMillis());
            error.put("platform", "android");
            error.put("version", prefs.getString("currentVersion", "base"));

            String errorUrl = baseUrl + "/api/error-report";
            sendPostRequest(errorUrl, error.toString());

        } catch (Exception e) {
            Log.w(TAG, "Failed to report error", e);
            // Don't throw - error reporting is optional
        }
    }

    /**
     * Reset to base version
     */
    public void resetToBase() {
        File updateDir = new File(context.getFilesDir(), "hot-updates");
        if (updateDir.exists()) {
            deleteRecursive(updateDir);
        }
        prefs.edit().putString("currentVersion", "base").apply();
        prefs.edit().remove("latestManifest").apply();
        prefs.edit().remove("updateFilePath").apply();
    }

    /**
     * Helper: Read text stream
     */
    private String readStream(InputStream stream) throws Exception {
        if (stream == null) return "";

        BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8));
        StringBuilder result = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) {
            result.append(line);
        }
        return result.toString();
    }

    /**
     * Helper: Read binary stream
     */
    private byte[] readBinaryStream(InputStream stream) throws Exception {
        byte[] buffer = new byte[8192];
        int bytesRead;
        byte[] result = new byte[0];

        while ((bytesRead = stream.read(buffer)) != -1) {
            byte[] newResult = new byte[result.length + bytesRead];
            System.arraycopy(result, 0, newResult, 0, result.length);
            System.arraycopy(buffer, 0, newResult, result.length, bytesRead);
            result = newResult;
        }

        return result;
    }

    /**
     * Helper: Calculate SHA-256 hash
     */
    private String sha256(byte[] data) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] hash = digest.digest(data);

        StringBuilder hexString = new StringBuilder();
        for (byte b : hash) {
            String hex = Integer.toHexString(0xff & b);
            if (hex.length() == 1) hexString.append('0');
            hexString.append(hex);
        }

        return hexString.toString();
    }

    /**
     * Helper: Send POST request
     */
    private String sendPostRequest(String urlString, String body) throws Exception {
        HttpURLConnection connection = null;
        try {
            URL url = new URL(urlString);
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Content-Type", "application/json");
            connection.setRequestProperty("X-API-Key", apiKey);
            connection.setDoOutput(true);
            connection.setConnectTimeout(CONNECT_TIMEOUT);
            connection.setReadTimeout(READ_TIMEOUT);

            try (OutputStream os = connection.getOutputStream()) {
                os.write(body.getBytes(StandardCharsets.UTF_8));
            }

            int responseCode = connection.getResponseCode();
            if (responseCode == HttpURLConnection.HTTP_OK) {
                return readStream(connection.getInputStream());
            } else {
                throw new Exception("POST request failed: HTTP " + responseCode);
            }

        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    /**
     * Helper: Delete directory recursively
     */
    private void deleteRecursive(File fileOrDirectory) {
        if (fileOrDirectory.isDirectory()) {
            for (File child : fileOrDirectory.listFiles()) {
                deleteRecursive(child);
            }
        }
        fileOrDirectory.delete();
    }
}
