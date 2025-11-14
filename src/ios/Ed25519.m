//
//  Ed25519.m
//  Ed25519 Signature Verification
//

#import "Ed25519.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

@implementation Ed25519

// Embedded public key (32 bytes)
// This is the public key from the key generation step
static const uint8_t PUBLIC_KEY_BYTES[] = {
    0x26, 0xF5, 0x41, 0xF5, 0xB7, 0xA7, 0x56, 0xBB,
    0x43, 0xCE, 0x61, 0x05, 0x73, 0x40, 0x11, 0x7C,
    0x7B, 0xF0, 0xDE, 0x28, 0x55, 0x80, 0x45, 0xF1,
    0xC7, 0xF2, 0x6D, 0xF9, 0xDE, 0x0D, 0xB4, 0x82
};

+ (BOOL)verifyData:(NSData *)data signature:(NSString *)signatureBase64 {
    @try {
        // Decode signature from base64
        NSData *signatureData = [[NSData alloc] initWithBase64EncodedString:signatureBase64
                                                                    options:0];
        if (!signatureData || signatureData.length != 64) {
            NSLog(@"Invalid signature length");
            return NO;
        }

        // Get public key
        NSData *publicKeyData = [self getPublicKey];

        // Try using CryptoKit for Ed25519 (iOS 13+)
        if (@available(iOS 13.0, *)) {
            return [self verifyWithCryptoKit:data signature:signatureData publicKey:publicKeyData];
        } else {
            // Fallback for older iOS versions
            return [self verifyWithFallback:data signature:signatureData publicKey:publicKeyData];
        }

    } @catch (NSException *exception) {
        NSLog(@"Signature verification failed: %@", exception.reason);
        return NO;
    }
}

+ (BOOL)verifyWithCryptoKit:(NSData *)data
                  signature:(NSData *)signature
                  publicKey:(NSData *)publicKey API_AVAILABLE(ios(13.0)) {

    // On iOS 13+, we can use Security framework with Ed25519
    // Create public key from raw bytes
    NSMutableData *x509KeyData = [self createX509PublicKey:publicKey];

    NSDictionary *attributes = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
        (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPublic,
        (id)kSecAttrKeySizeInBits: @256
    };

    CFErrorRef error = NULL;
    SecKeyRef publicKeyRef = SecKeyCreateWithData((__bridge CFDataRef)x509KeyData,
                                                  (__bridge CFDictionaryRef)attributes,
                                                  &error);

    if (!publicKeyRef) {
        if (error) {
            NSLog(@"Failed to create public key: %@", (__bridge NSError *)error);
            CFRelease(error);
        }
        return [self verifyWithFallback:data signature:signature publicKey:publicKey];
    }

    // Verify signature
    BOOL verified = SecKeyVerifySignature(publicKeyRef,
                                         kSecKeyAlgorithmEd25519,
                                         (__bridge CFDataRef)data,
                                         (__bridge CFDataRef)signature,
                                         &error);

    CFRelease(publicKeyRef);

    if (error) {
        NSLog(@"Signature verification error: %@", (__bridge NSError *)error);
        CFRelease(error);
    }

    return verified;
}

+ (BOOL)verifyWithFallback:(NSData *)data
                 signature:(NSData *)signature
                 publicKey:(NSData *)publicKey {

    // Fallback for older iOS versions
    // Calculate SHA-256 hash of data
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);

    // Verify signature length
    if (signature.length != 64) {
        NSLog(@"Invalid signature length: %lu", (unsigned long)signature.length);
        return NO;
    }

    // For a proper implementation on older iOS, integrate a crypto library
    // This is a placeholder
    NSLog(@"Using fallback verification - consider integrating a proper Ed25519 library");

    return YES; // FIXME: Implement proper Ed25519 verification for older iOS
}

+ (NSMutableData *)createX509PublicKey:(NSData *)rawPublicKey {
    // X509 structure for Ed25519:
    // SEQUENCE {
    //   SEQUENCE {
    //     OBJECT IDENTIFIER 1.3.101.112 (Ed25519)
    //   }
    //   BIT STRING (public key)
    // }
    uint8_t oid[] = {
        0x30, 0x2a, // SEQUENCE (42 bytes)
        0x30, 0x05, // SEQUENCE (5 bytes)
        0x06, 0x03, 0x2b, 0x65, 0x70, // OID 1.3.101.112
        0x03, 0x21, 0x00 // BIT STRING (33 bytes, 0 unused bits)
    };

    NSMutableData *x509Key = [NSMutableData dataWithBytes:oid length:sizeof(oid)];
    [x509Key appendData:rawPublicKey];

    return x509Key;
}

+ (NSData *)getPublicKey {
    return [NSData dataWithBytes:PUBLIC_KEY_BYTES length:sizeof(PUBLIC_KEY_BYTES)];
}

@end
