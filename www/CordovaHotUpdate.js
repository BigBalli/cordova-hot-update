/**
 * Cordova Hot Update Plugin
 * JavaScript interface for secure remote code updates
 */

var exec = require('cordova/exec');

var CordovaHotUpdate = {

    /**
     * Initialize the plugin with app credentials
     * @param {Object} options - Configuration options
     * @param {string} options.appId - App ID from dashboard
     * @param {string} options.apiKey - API key from dashboard
     * @param {string} [options.baseUrl] - Base URL for update server (default: https://cordova-hot-update.com)
     * @param {Function} success - Success callback
     * @param {Function} error - Error callback
     */
    initialize: function(options, success, error) {
        if (!options || !options.appId || !options.apiKey) {
            if (error) error('appId and apiKey are required');
            return;
        }

        options.baseUrl = options.baseUrl || 'https://cordova-hot-update.com';

        exec(success, error, 'CordovaHotUpdate', 'initialize', [options]);
    },

    /**
     * Check if a new update is available
     * @param {Function} success - Success callback with update info {available: boolean, version: string, size: number}
     * @param {Function} error - Error callback
     */
    checkForUpdate: function(success, error) {
        exec(success, error, 'CordovaHotUpdate', 'checkForUpdate', []);
    },

    /**
     * Download and apply the available update
     * @param {Function} success - Success callback
     * @param {Function} error - Error callback
     * @param {Function} [progress] - Progress callback with percentage (0-100)
     */
    applyUpdate: function(success, error, progress) {
        var progressCallback = progress ? function(percent) {
            progress(percent);
        } : null;

        exec(success, error, 'CordovaHotUpdate', 'applyUpdate', [progressCallback]);
    },

    /**
     * Get the currently installed update version
     * @param {Function} success - Success callback with version string
     * @param {Function} error - Error callback
     */
    getCurrentVersion: function(success, error) {
        exec(success, error, 'CordovaHotUpdate', 'getCurrentVersion', []);
    },

    /**
     * Enable or disable automatic error reporting
     * @param {boolean} enable - Enable/disable error reporting
     * @param {Function} success - Success callback
     * @param {Function} error - Error callback
     */
    enableErrorReporting: function(enable, success, error) {
        exec(success, error, 'CordovaHotUpdate', 'enableErrorReporting', [enable]);
    },

    /**
     * Manually report an error
     * @param {string} message - Error message
     * @param {string} [stack] - Error stack trace
     * @param {Function} success - Success callback
     * @param {Function} error - Error callback
     */
    reportError: function(message, stack, success, error) {
        exec(success, error, 'CordovaHotUpdate', 'reportError', [message, stack || '']);
    },

    /**
     * Get plugin info and status
     * @param {Function} success - Success callback with status object
     * @param {Function} error - Error callback
     */
    getStatus: function(success, error) {
        exec(success, error, 'CordovaHotUpdate', 'getStatus', []);
    },

    /**
     * Clear cached updates and reset to base version
     * @param {Function} success - Success callback
     * @param {Function} error - Error callback
     */
    resetToBase: function(success, error) {
        exec(success, error, 'CordovaHotUpdate', 'resetToBase', []);
    }
};

// Auto-initialize error reporting if enabled
if (window) {
    // Store original error handler
    var originalOnError = window.onerror;

    // Override window.onerror to capture errors
    window.onerror = function(message, source, lineno, colno, error) {
        // Report to plugin
        CordovaHotUpdate.reportError(
            message || 'Unknown error',
            error && error.stack ? error.stack : (source + ':' + lineno + ':' + colno),
            function() {}, // success
            function() {}  // error (silently fail)
        );

        // Call original handler if it exists
        if (originalOnError && typeof originalOnError === 'function') {
            return originalOnError(message, source, lineno, colno, error);
        }

        return false;
    };
}

module.exports = CordovaHotUpdate;
