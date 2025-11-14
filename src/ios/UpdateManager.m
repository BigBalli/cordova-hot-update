//
//  UpdateManager.m
//  Update Manager for iOS
//

#import "UpdateManager.h"
#import "Ed25519.h"
#import <CommonCrypto/CommonCrypto.h>

@interface UpdateManager ()

@property (nonatomic, strong) NSUserDefaults *prefs;
@property (nonatomic, strong) NSString *appId;
@property (nonatomic, strong) NSString *apiKey;
@property (nonatomic, strong) NSString *baseUrl;

@end

@implementation UpdateManager

- (instancetype)initWithPrefs:(NSUserDefaults *)prefs {
    self = [super init];
    if (self) {
        self.prefs = prefs;
    }
    return self;
}

- (void)setCredentialsWithAppId:(NSString *)appId
                        apiKey:(NSString *)apiKey
                       baseUrl:(NSString *)baseUrl {
    self.appId = appId;
    self.apiKey = apiKey;
    self.baseUrl = baseUrl;
}

- (NSString *)getNativeAppVersion {
    // Get version from Info.plist (CFBundleShortVersionString)
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return version ?: @"unknown";
}

- (NSDictionary *)checkForUpdate {
    NSString *nativeAppVersion = [self getNativeAppVersion];
    NSString *manifestUrl = [NSString stringWithFormat:@"%@/api/manifest?appId=%@&nativeAppVersion=%@",
                            self.baseUrl, self.appId, nativeAppVersion];

    NSLog(@"Checking for update: %@ (app version: %@)", manifestUrl, nativeAppVersion);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:manifestUrl]];
    [request setHTTPMethod:@"GET"];
    [request setValue:self.apiKey forHTTPHeaderField:@"X-API-Key"];
    [request setTimeoutInterval:15.0];

    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request
                                        returningResponse:&response
                                                    error:&error];

    if (error) {
        @throw [NSException exceptionWithName:@"NetworkError"
                                       reason:error.localizedDescription
                                     userInfo:nil];
    }

    if (response.statusCode == 200) {
        NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:0
                                                                   error:&error];
        if (error) {
            @throw [NSException exceptionWithName:@"ParseError"
                                           reason:error.localizedDescription
                                         userInfo:nil];
        }

        // Save manifest for later use
        NSString *manifestJson = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self.prefs setObject:manifestJson forKey:@"latestManifest"];
        [self.prefs setDouble:[[NSDate date] timeIntervalSince1970] forKey:@"lastCheckTime"];
        [self.prefs synchronize];

        // Send metrics with hotfix version from manifest or current installed version
        NSString *hotfixVersion = manifest[@"hotfixVersion"] ?: ([self.prefs stringForKey:@"hotfixVersion"] ?: @"base");
        [self sendMetrics:@"check" version:hotfixVersion];

        return manifest;

    } else if (response.statusCode == 429) {
        @throw [NSException exceptionWithName:@"RateLimitError"
                                       reason:@"Rate limit exceeded"
                                     userInfo:nil];
    } else {
        NSString *errorMsg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        @throw [NSException exceptionWithName:@"ServerError"
                                       reason:[NSString stringWithFormat:@"Server error: %@", errorMsg]
                                     userInfo:nil];
    }
}

- (BOOL)downloadAndApplyUpdate {
    NSString *manifestJson = [self.prefs stringForKey:@"latestManifest"];
    if (!manifestJson) {
        @throw [NSException exceptionWithName:@"NoUpdateError"
                                       reason:@"No update available. Call checkForUpdate first."
                                     userInfo:nil];
    }

    NSError *error = nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:[manifestJson dataUsingEncoding:NSUTF8StringEncoding]
                                                             options:0
                                                               error:&error];
    if (error) {
        @throw [NSException exceptionWithName:@"ParseError"
                                       reason:error.localizedDescription
                                     userInfo:nil];
    }

    if (![manifest[@"available"] boolValue]) {
        return NO;
    }

    NSString *hotfixVersion = manifest[@"hotfixVersion"];
    NSString *nativeAppVersion = manifest[@"nativeAppVersion"];
    NSString *downloadUrl = manifest[@"url"];
    NSString *expectedHash = manifest[@"hash"];
    NSString *signature = manifest[@"signature"];

    NSLog(@"Downloading hotfix version: %@ for app version: %@", hotfixVersion, nativeAppVersion);

    // Download the bundle
    NSData *bundle = [self downloadBundleFromUrl:downloadUrl];

    // Verify hash
    NSString *actualHash = [self sha256:bundle];
    if (![actualHash isEqualToString:expectedHash]) {
        NSLog(@"Hash mismatch! Expected: %@, Got: %@", expectedHash, actualHash);
        @throw [NSException exceptionWithName:@"VerificationError"
                                       reason:@"Update verification failed: hash mismatch"
                                     userInfo:nil];
    }

    // Verify signature
    if (![Ed25519 verifyData:bundle signature:signature]) {
        NSLog(@"Signature verification failed!");
        @throw [NSException exceptionWithName:@"VerificationError"
                                       reason:@"Update verification failed: invalid signature"
                                     userInfo:nil];
    }

    // Inject global variable before the hotfix code
    NSString *globalVarInjection = [NSString stringWithFormat:@"window.CordovaHotUpdateCurrentAppVersion = \"%@\";\n\n", nativeAppVersion];
    NSMutableData *finalBundle = [NSMutableData dataWithData:[globalVarInjection dataUsingEncoding:NSUTF8StringEncoding]];
    [finalBundle appendData:bundle];

    // Save the bundle with injection (always overwrites - only one hotfix file)
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *updateDir = [documentsDirectory stringByAppendingPathComponent:@"hot-updates"];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:updateDir]) {
        [fileManager createDirectoryAtPath:updateDir
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];
    }

    NSString *updateFile = [updateDir stringByAppendingPathComponent:@"hotfix.js"];
    [finalBundle writeToFile:updateFile atomically:YES];

    // Store file path and metadata
    [self.prefs setObject:hotfixVersion forKey:@"hotfixVersion"]; // Just for display
    [self.prefs setObject:updateFile forKey:@"updateFilePath"];
    [self.prefs setDouble:[[NSDate date] timeIntervalSince1970] forKey:@"lastDownloadTime"];
    [self.prefs synchronize];

    // Send metrics
    [self sendMetrics:@"download" version:hotfixVersion];

    NSLog(@"Hotfix applied: %@ (app version: %@)", hotfixVersion, nativeAppVersion);

    return YES;
}

- (NSData *)downloadBundleFromUrl:(NSString *)urlString {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"GET"];
    [request setValue:self.apiKey forHTTPHeaderField:@"X-API-Key"];
    [request setTimeoutInterval:15.0];

    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request
                                        returningResponse:&response
                                                    error:&error];

    if (error) {
        @throw [NSException exceptionWithName:@"NetworkError"
                                       reason:error.localizedDescription
                                     userInfo:nil];
    }

    if (response.statusCode != 200) {
        @throw [NSException exceptionWithName:@"DownloadError"
                                       reason:[NSString stringWithFormat:@"Failed to download bundle: HTTP %ld", (long)response.statusCode]
                                     userInfo:nil];
    }

    return data;
}

- (void)sendMetrics:(NSString *)action version:(NSString *)version {
    @try {
        NSDictionary *metrics = @{
            @"appId": self.appId,
            @"action": action,
            @"version": version,
            @"timestamp": @([[NSDate date] timeIntervalSince1970] * 1000),
            @"platform": @"ios"
        };

        NSString *metricsUrl = [NSString stringWithFormat:@"%@/api/metrics", self.baseUrl];
        [self sendPostRequest:metricsUrl body:metrics];

    } @catch (NSException *exception) {
        NSLog(@"Failed to send metrics: %@", exception.reason);
        // Don't throw - metrics are optional
    }
}

- (void)reportErrorWithMessage:(NSString *)message stack:(NSString *)stack {
    @try {
        NSString *currentVersion = [self.prefs stringForKey:@"currentVersion"] ?: @"base";

        NSDictionary *errorReport = @{
            @"appId": self.appId,
            @"message": message,
            @"stack": stack,
            @"timestamp": @([[NSDate date] timeIntervalSince1970] * 1000),
            @"platform": @"ios",
            @"version": currentVersion
        };

        NSString *errorUrl = [NSString stringWithFormat:@"%@/api/error-report", self.baseUrl];
        [self sendPostRequest:errorUrl body:errorReport];

    } @catch (NSException *exception) {
        NSLog(@"Failed to report error: %@", exception.reason);
        // Don't throw - error reporting is optional
    }
}

- (void)resetToBase {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *updateDir = [documentsDirectory stringByAppendingPathComponent:@"hot-updates"];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:updateDir]) {
        [fileManager removeItemAtPath:updateDir error:nil];
    }

    [self.prefs setObject:@"base" forKey:@"currentVersion"];
    [self.prefs removeObjectForKey:@"latestManifest"];
    [self.prefs removeObjectForKey:@"updateFilePath"];
    [self.prefs synchronize];
}

- (NSString *)sha256:(NSData *)data {
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);

    NSMutableString *hexString = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hexString appendFormat:@"%02x", hash[i]];
    }

    return hexString;
}

- (void)sendPostRequest:(NSString *)urlString body:(NSDictionary *)body {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    if (error) {
        @throw [NSException exceptionWithName:@"SerializationError"
                                       reason:error.localizedDescription
                                     userInfo:nil];
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:self.apiKey forHTTPHeaderField:@"X-API-Key"];
    [request setHTTPBody:jsonData];
    [request setTimeoutInterval:15.0];

    NSHTTPURLResponse *response = nil;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    if (error) {
        @throw [NSException exceptionWithName:@"NetworkError"
                                       reason:error.localizedDescription
                                     userInfo:nil];
    }

    if (response.statusCode != 200) {
        @throw [NSException exceptionWithName:@"PostError"
                                       reason:[NSString stringWithFormat:@"POST request failed: HTTP %ld", (long)response.statusCode]
                                     userInfo:nil];
    }
}

@end
