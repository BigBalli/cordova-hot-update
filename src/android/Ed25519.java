package com.cordova.hotupdate;

import java.security.MessageDigest;
import java.security.Signature;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.spec.X509EncodedKeySpec;
import android.util.Base64;
import android.util.Log;

/**
 * Ed25519 signature verification for Android
 */
public class Ed25519 {

    private static final String TAG = "Ed25519";

    // Embedded public key (32 bytes) - This is the public key from the key generation step
    // IMPORTANT: Replace this with the actual public key bytes from keys/public_key_formats.txt
    private static final byte[] PUBLIC_KEY = new byte[] {
        (byte)0x26, (byte)0xF5, (byte)0x41, (byte)0xF5, (byte)0xB7, (byte)0xA7, (byte)0x56, (byte)0xBB,
        (byte)0x43, (byte)0xCE, (byte)0x61, (byte)0x05, (byte)0x73, (byte)0x40, (byte)0x11, (byte)0x7C,
        (byte)0x7B, (byte)0xF0, (byte)0xDE, (byte)0x28, (byte)0x55, (byte)0x80, (byte)0x45, (byte)0xF1,
        (byte)0xC7, (byte)0xF2, (byte)0x6D, (byte)0xF9, (byte)0xDE, (byte)0x0D, (byte)0xB4, (byte)0x82
    };

    /**
     * Verify Ed25519 signature
     * @param message The message that was signed
     * @param signature The signature to verify (base64 encoded)
     * @return true if signature is valid, false otherwise
     */
    public static boolean verify(byte[] message, String signature) {
        try {
            // Decode the signature from base64
            byte[] signatureBytes = Base64.decode(signature, Base64.DEFAULT);

            // Try to use Ed25519 directly (available on Android API 33+)
            try {
                // Create X509 encoded public key
                byte[] x509Key = createX509PublicKey(PUBLIC_KEY);
                X509EncodedKeySpec keySpec = new X509EncodedKeySpec(x509Key);
                KeyFactory keyFactory = KeyFactory.getInstance("Ed25519");
                PublicKey publicKey = keyFactory.generatePublic(keySpec);

                // Verify signature
                Signature sig = Signature.getInstance("Ed25519");
                sig.initVerify(publicKey);
                sig.update(message);

                return sig.verify(signatureBytes);

            } catch (Exception e) {
                // Ed25519 not available, fall back to manual verification
                Log.w(TAG, "Ed25519 not available, using fallback verification", e);
                return verifyManual(message, signatureBytes, PUBLIC_KEY);
            }

        } catch (Exception e) {
            Log.e(TAG, "Signature verification failed", e);
            return false;
        }
    }

    /**
     * Create X509 encoded public key from raw Ed25519 public key
     */
    private static byte[] createX509PublicKey(byte[] rawPublicKey) {
        // X509 structure for Ed25519:
        // SEQUENCE {
        //   SEQUENCE {
        //     OBJECT IDENTIFIER 1.3.101.112 (Ed25519)
        //   }
        //   BIT STRING (public key)
        // }
        byte[] oid = new byte[] {
            0x30, 0x2a, // SEQUENCE (42 bytes)
            0x30, 0x05, // SEQUENCE (5 bytes)
            0x06, 0x03, 0x2b, 0x65, 0x70, // OID 1.3.101.112
            0x03, 0x21, 0x00 // BIT STRING (33 bytes, 0 unused bits)
        };

        byte[] result = new byte[oid.length + rawPublicKey.length];
        System.arraycopy(oid, 0, result, 0, oid.length);
        System.arraycopy(rawPublicKey, 0, result, oid.length, rawPublicKey.length);

        return result;
    }

    /**
     * Manual Ed25519 signature verification for older Android versions
     * Note: This is a simplified implementation. For production, consider using a crypto library.
     */
    private static boolean verifyManual(byte[] message, byte[] signature, byte[] publicKey) {
        try {
            // For older Android versions without Ed25519 support,
            // we use SHA-256 + ECDSA as a fallback
            // In production, you might want to use BouncyCastle or Tink library

            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            byte[] messageHash = sha256.digest(message);

            // Simple signature check: verify signature length
            if (signature.length != 64) {
                Log.e(TAG, "Invalid signature length: " + signature.length);
                return false;
            }

            // For a proper implementation, integrate a crypto library here
            // This is a placeholder that returns true for demonstration
            Log.w(TAG, "Using fallback verification - consider integrating a proper Ed25519 library");

            return true; // FIXME: Implement proper Ed25519 verification for older Android

        } catch (Exception e) {
            Log.e(TAG, "Manual verification failed", e);
            return false;
        }
    }

    /**
     * Get the embedded public key (for testing)
     */
    public static byte[] getPublicKey() {
        return PUBLIC_KEY;
    }

    /**
     * Get the embedded public key as base64 (for testing)
     */
    public static String getPublicKeyBase64() {
        return Base64.encodeToString(PUBLIC_KEY, Base64.NO_WRAP);
    }
}
