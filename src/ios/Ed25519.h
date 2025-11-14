//
//  Ed25519.h
//  Ed25519 Signature Verification
//

#import <Foundation/Foundation.h>

@interface Ed25519 : NSObject

+ (BOOL)verifyData:(NSData *)data signature:(NSString *)signatureBase64;
+ (NSData *)getPublicKey;

@end
