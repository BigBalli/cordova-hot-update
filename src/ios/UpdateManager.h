//
//  UpdateManager.h
//  Update Manager for iOS
//

#import <Foundation/Foundation.h>

@interface UpdateManager : NSObject

- (instancetype)initWithPrefs:(NSUserDefaults *)prefs;
- (void)setCredentialsWithAppId:(NSString *)appId
                        apiKey:(NSString *)apiKey
                       baseUrl:(NSString *)baseUrl;
- (NSDictionary *)checkForUpdate;
- (BOOL)downloadAndApplyUpdate;
- (void)sendMetrics:(NSString *)action version:(NSString *)version;
- (void)reportErrorWithMessage:(NSString *)message stack:(NSString *)stack;
- (void)resetToBase;

@end
