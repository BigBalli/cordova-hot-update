# Cordova Hot Update Plugin

A Cordova plugin enabling secure remote JavaScript updates for apps distributed through app stores.

## Installation

```bash
cordova plugin add cordova-hot-update
```

## Quick Start

1. Register your app at [cordova-hot-update.com](https://cordova-hot-update.com)
2. Get your App ID and API Key
3. Configure your app:

```javascript
// Initialize the plugin
cordova.plugins.hotUpdate.initialize({
    appId: 'YOUR_APP_ID',
    apiKey: 'YOUR_API_KEY'
}, function() {
    console.log('Hot Update initialized');
}, function(error) {
    console.error('Initialization failed:', error);
});

// Check for updates
cordova.plugins.hotUpdate.checkForUpdate(function(result) {
    if (result.available) {
        console.log('Update available:', result.version);

        // Download and apply update
        cordova.plugins.hotUpdate.applyUpdate(function() {
            console.log('Update applied successfully');
        }, function(error) {
            console.error('Update failed:', error);
        });
    }
}, function(error) {
    console.error('Check failed:', error);
});
```

## API Reference

### initialize(options, success, error)

Initialize the plugin with your app credentials.

**Parameters:**
- `options` (Object):
  - `appId` (String): Your app ID from the dashboard
  - `apiKey` (String): Your API key from the dashboard
- `success` (Function): Success callback
- `error` (Function): Error callback

### checkForUpdate(success, error)

Check if a new update is available.

**Parameters:**
- `success` (Function): Callback with update info `{available: boolean, version: string}`
- `error` (Function): Error callback

### applyUpdate(success, error)

Download and apply the available update.

**Parameters:**
- `success` (Function): Success callback
- `error` (Function): Error callback

### getCurrentVersion(success, error)

Get the currently installed update version.

**Parameters:**
- `success` (Function): Callback with version string
- `error` (Function): Error callback

### enableErrorReporting(enable, success, error)

Enable or disable automatic error reporting.

**Parameters:**
- `enable` (Boolean): Enable/disable error reporting
- `success` (Function): Success callback
- `error` (Function): Error callback

## Features

- Secure updates with Ed25519 signature verification
- Hotfix deployment to all app versions
- Access to native app version in hotfix code
- Error reporting and analytics
- Platform targeting (iOS/Android)
- Fallback to previous version on failure

## How Updates Work

This plugin uses an **always-fresh hotfix system**:

- **Always Fetch Latest**: Every app launch fetches the latest hotfix from the server (no caching)
- **One Active Hotfix**: Only ONE hotfix exists at any time - updating replaces the old one
- **Version Label**: Optional label for developer tracking only (e.g., "fix-login-bug", timestamp)
- **Native App Version**: Automatically detected from Info.plist (iOS) or build.gradle (Android)

**Important:** Apps **always download** the current hotfix on every launch. There is no version comparison or caching.

### Accessing Native App Version in Hotfix Code

The plugin automatically injects a global variable before executing your hotfix:

```javascript
// This variable is automatically available in your hotfix code
console.log(window.CordovaHotUpdateCurrentAppVersion); // e.g., "1.0.0" or "1.0.1"

// Example: Version-specific hotfix logic
if (window.CordovaHotUpdateCurrentAppVersion === '1.0.0') {
    // Fix specific to version 1.0.0
    window.oldApiBugWorkaround = function() {
        // Workaround for bug only present in v1.0.0
    };
} else if (window.CordovaHotUpdateCurrentAppVersion >= '1.0.1') {
    // Enhancement for v1.0.1+
    window.newFeature = function() {
        // New functionality
    };
}

// Global fixes apply to all versions
window.criticalBugFix = function() {
    // This runs on all app versions
};
```

## Security

All updates are:
1. Fetched from your configured source URL by our backend
2. Encrypted and signed with Ed25519
3. Verified by the plugin before execution
4. Never executed if signature verification fails

## Support

- Dashboard: https://cordova-hot-update.com
- Issues: https://github.com/yourusername/cordova-hot-update/issues
- Docs: https://docs.cordova-hot-update.com

## License

MIT
