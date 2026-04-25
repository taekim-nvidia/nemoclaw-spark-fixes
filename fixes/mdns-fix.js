/**
 * nemoclaw-mdns-fix.js
 *
 * Monkey-patches os.networkInterfaces() to return an empty object instead of
 * throwing when uv_interface_addresses fails inside OpenShell's restricted
 * network namespace (ERR_SYSTEM_ERROR / "Unknown system error 1").
 *
 * Without this patch, homebridge/ciao raises an unhandled rejection on
 * OpenClaw startup. OpenClaw's global error handler re-throws it as an
 * uncaughtException, crashing the gateway ~20ms after it starts listening.
 *
 * Load via NODE_OPTIONS=--require /path/to/mdns-fix.js
 *
 * NemoClaw bug report: https://github.com/taekim-nvidia/nemoclaw-spark-fixes
 * Affected: OpenClaw 2026.4.2, OpenShell 0.0.36, NemoClaw 0.1.0
 * Fixed in: OpenClaw 2026.4.23+ (upstream image not yet published)
 */
(function () {
  'use strict';
  var os = require('os');
  var _orig = os.networkInterfaces;
  os.networkInterfaces = function () {
    try {
      return _orig.call(os);
    } catch (e) {
      if (
        e.code === 'ERR_SYSTEM_ERROR' ||
        String(e).indexOf('uv_interface_addresses') !== -1
      ) {
        process.stderr.write(
          '[nemoclaw-mdns-fix] os.networkInterfaces() failed in restricted netns — returning empty (ciao mDNS disabled)\n'
        );
        return {};
      }
      throw e;
    }
  };
})();
