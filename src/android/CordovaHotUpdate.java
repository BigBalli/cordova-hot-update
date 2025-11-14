package com.cordova.hotupdate;

import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * Cordova Hot Update Plugin - Main plugin class for Android
 */
public class CordovaHotUpdate extends CordovaPlugin {

    private static final String TAG = "CordovaHotUpdate";
    private static final String PREFS_NAME = "CordovaHotUpdatePrefs";

    private UpdateManager updateManager;
    private SharedPreferences prefs;

    @Override
    protected void pluginInitialize() {
        super.pluginInitialize();
        Context context = cordova.getActivity().getApplicationContext();
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        updateManager = new UpdateManager(context, prefs);
    }

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {

        switch (action) {
            case "initialize":
                return this.initialize(args.getJSONObject(0), callbackContext);

            case "checkForUpdate":
                return this.checkForUpdate(callbackContext);

            case "applyUpdate":
                return this.applyUpdate(callbackContext);

            case "getCurrentVersion":
                return this.getCurrentVersion(callbackContext);

            case "enableErrorReporting":
                return this.enableErrorReporting(args.getBoolean(0), callbackContext);

            case "reportError":
                return this.reportError(args.getString(0), args.getString(1), callbackContext);

            case "getStatus":
                return this.getStatus(callbackContext);

            case "resetToBase":
                return this.resetToBase(callbackContext);

            case "loadStoredUpdate":
                return this.loadStoredUpdate(callbackContext);

            default:
                return false;
        }
    }

    /**
     * Initialize the plugin with app credentials
     */
    private boolean initialize(JSONObject options, CallbackContext callbackContext) {
        try {
            String appId = options.getString("appId");
            String apiKey = options.getString("apiKey");
            String baseUrl = options.optString("baseUrl", "https://cordova-hot-update.com");

            // Save credentials
            SharedPreferences.Editor editor = prefs.edit();
            editor.putString("appId", appId);
            editor.putString("apiKey", apiKey);
            editor.putString("baseUrl", baseUrl);
            editor.putBoolean("initialized", true);
            editor.apply();

            updateManager.setCredentials(appId, apiKey, baseUrl);

            callbackContext.success("Initialized successfully");
            return true;

        } catch (JSONException e) {
            callbackContext.error("Invalid options: " + e.getMessage());
            return false;
        }
    }

    /**
     * Check if a new update is available
     */
    private boolean checkForUpdate(CallbackContext callbackContext) {
        if (!isInitialized()) {
            callbackContext.error("Plugin not initialized");
            return true;
        }

        cordova.getThreadPool().execute(new Runnable() {
            @Override
            public void run() {
                try {
                    JSONObject result = updateManager.checkForUpdate();
                    callbackContext.success(result);
                } catch (Exception e) {
                    callbackContext.error("Failed to check for update: " + e.getMessage());
                }
            }
        });

        return true;
    }

    /**
     * Download and apply the available update
     */
    private boolean applyUpdate(CallbackContext callbackContext) {
        if (!isInitialized()) {
            callbackContext.error("Plugin not initialized");
            return true;
        }

        cordova.getThreadPool().execute(new Runnable() {
            @Override
            public void run() {
                try {
                    boolean success = updateManager.downloadAndApplyUpdate();
                    if (success) {
                        // Execute the hotfix immediately
                        String updateFilePath = prefs.getString("updateFilePath", null);
                        if (updateFilePath != null) {
                            java.io.File updateFile = new java.io.File(updateFilePath);
                            if (updateFile.exists()) {
                                // Read the file content
                                java.io.FileInputStream fis = new java.io.FileInputStream(updateFile);
                                byte[] data = new byte[(int) updateFile.length()];
                                fis.read(data);
                                fis.close();

                                final String jsCode = new String(data, "UTF-8");

                                android.util.Log.d(TAG, "[CordovaHotUpdate] Executing hotfix immediately...");

                                // Execute on UI thread
                                cordova.getActivity().runOnUiThread(new Runnable() {
                                    @Override
                                    public void run() {
                                        webView.loadUrl("javascript:" + jsCode);
                                        android.util.Log.d(TAG, "[CordovaHotUpdate] Hotfix executed successfully");
                                    }
                                });
                            }
                        }

                        callbackContext.success("Update applied successfully");
                    } else {
                        callbackContext.error("Failed to apply update");
                    }
                } catch (Exception e) {
                    callbackContext.error("Failed to apply update: " + e.getMessage());
                }
            }
        });

        return true;
    }

    /**
     * Get the currently installed update version
     */
    private boolean getCurrentVersion(CallbackContext callbackContext) {
        String version = prefs.getString("currentVersion", "base");
        callbackContext.success(version);
        return true;
    }

    /**
     * Enable or disable automatic error reporting
     */
    private boolean enableErrorReporting(boolean enable, CallbackContext callbackContext) {
        SharedPreferences.Editor editor = prefs.edit();
        editor.putBoolean("errorReportingEnabled", enable);
        editor.apply();

        callbackContext.success("Error reporting " + (enable ? "enabled" : "disabled"));
        return true;
    }

    /**
     * Manually report an error
     */
    private boolean reportError(String message, String stack, CallbackContext callbackContext) {
        if (!isInitialized()) {
            callbackContext.error("Plugin not initialized");
            return true;
        }

        boolean enabled = prefs.getBoolean("errorReportingEnabled", false);
        if (!enabled) {
            callbackContext.success("Error reporting is disabled");
            return true;
        }

        cordova.getThreadPool().execute(new Runnable() {
            @Override
            public void run() {
                try {
                    updateManager.reportError(message, stack);
                    callbackContext.success("Error reported");
                } catch (Exception e) {
                    callbackContext.error("Failed to report error: " + e.getMessage());
                }
            }
        });

        return true;
    }

    /**
     * Get plugin info and status
     */
    private boolean getStatus(CallbackContext callbackContext) {
        try {
            JSONObject status = new JSONObject();
            status.put("initialized", isInitialized());
            status.put("currentVersion", prefs.getString("currentVersion", "base"));
            status.put("errorReportingEnabled", prefs.getBoolean("errorReportingEnabled", false));
            status.put("lastCheckTime", prefs.getLong("lastCheckTime", 0));

            callbackContext.success(status);
            return true;
        } catch (JSONException e) {
            callbackContext.error("Failed to get status: " + e.getMessage());
            return false;
        }
    }

    /**
     * Clear cached updates and reset to base version
     */
    private boolean resetToBase(CallbackContext callbackContext) {
        cordova.getThreadPool().execute(new Runnable() {
            @Override
            public void run() {
                try {
                    updateManager.resetToBase();

                    SharedPreferences.Editor editor = prefs.edit();
                    editor.putString("currentVersion", "base");
                    editor.apply();

                    callbackContext.success("Reset to base version");
                } catch (Exception e) {
                    callbackContext.error("Failed to reset: " + e.getMessage());
                }
            }
        });

        return true;
    }

    /**
     * Load and return the stored update from disk
     */
    private boolean loadStoredUpdate(CallbackContext callbackContext) {
        cordova.getThreadPool().execute(new Runnable() {
            @Override
            public void run() {
                try {
                    // Get the stored update file path
                    String updateFilePath = prefs.getString("updateFilePath", null);

                    if (updateFilePath == null) {
                        // No update stored
                        callbackContext.success("");
                        return;
                    }

                    // Check if file exists
                    java.io.File updateFile = new java.io.File(updateFilePath);
                    if (!updateFile.exists()) {
                        android.util.Log.d(TAG, "Update file not found at path: " + updateFilePath);
                        callbackContext.success("");
                        return;
                    }

                    // Read the file content
                    java.io.FileInputStream fis = new java.io.FileInputStream(updateFile);
                    byte[] data = new byte[(int) updateFile.length()];
                    fis.read(data);
                    fis.close();

                    String jsCode = new String(data, "UTF-8");

                    android.util.Log.d(TAG, "Loaded update from: " + updateFilePath);

                    // Return the JavaScript code
                    callbackContext.success(jsCode);

                } catch (Exception e) {
                    android.util.Log.e(TAG, "Exception loading update: " + e.getMessage());
                    callbackContext.error("Failed to load update: " + e.getMessage());
                }
            }
        });

        return true;
    }

    /**
     * Check if plugin is initialized
     */
    private boolean isInitialized() {
        return prefs.getBoolean("initialized", false);
    }
}
