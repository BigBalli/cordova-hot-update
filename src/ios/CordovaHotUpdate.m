//
//  CordovaHotUpdate.m
//  Cordova Hot Update Plugin
//

#import "CordovaHotUpdate.h"
#import "UpdateManager.h"

@interface CordovaHotUpdate ()

@property (nonatomic, strong) UpdateManager *updateManager;
@property (nonatomic, strong) NSUserDefaults *prefs;

@end

@implementation CordovaHotUpdate

- (void)pluginInitialize {
    [super pluginInitialize];
    self.prefs = [NSUserDefaults standardUserDefaults];
    self.updateManager = [[UpdateManager alloc] initWithPrefs:self.prefs];
}

- (void)initialize:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate runInBackground:^{
        @try {
            NSDictionary *options = [command.arguments objectAtIndex:0];
            NSString *appId = options[@"appId"];
            NSString *apiKey = options[@"apiKey"];
            NSString *baseUrl = options[@"baseUrl"] ?: @"https://cordova-hot-update.com";

            if (!appId || !apiKey) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                            messageAsString:@"appId and apiKey are required"];
                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
                return;
            }

            // Save credentials
            [self.prefs setObject:appId forKey:@"appId"];
            [self.prefs setObject:apiKey forKey:@"apiKey"];
            [self.prefs setObject:baseUrl forKey:@"baseUrl"];
            [self.prefs setBool:YES forKey:@"initialized"];
            [self.prefs synchronize];

            [self.updateManager setCredentialsWithAppId:appId apiKey:apiKey baseUrl:baseUrl];

            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                        messageAsString:@"Initialized successfully"];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];

        } @catch (NSException *exception) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                        messageAsString:exception.reason];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        }
    }];
}

- (void)checkForUpdate:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate runInBackground:^{
        if (![self isInitialized]) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                        messageAsString:@"Plugin not initialized"];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            return;
        }

        @try {
            NSDictionary *manifest = [self.updateManager checkForUpdate];

            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                     messageAsDictionary:manifest];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];

        } @catch (NSException *exception) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                        messageAsString:exception.reason];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        }
    }];
}

- (void)applyUpdate:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate runInBackground:^{
        if (![self isInitialized]) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                        messageAsString:@"Plugin not initialized"];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            return;
        }

        @try {
            BOOL success = [self.updateManager downloadAndApplyUpdate];

            if (success) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                            messageAsString:@"Update applied successfully"];
                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            } else {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                            messageAsString:@"Failed to apply update"];
                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            }

        } @catch (NSException *exception) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                        messageAsString:exception.reason];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        }
    }];
}

- (void)getCurrentVersion:(CDVInvokedUrlCommand*)command {
    NSString *version = [self.prefs stringForKey:@"currentVersion"] ?: @"base";

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                messageAsString:version];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)enableErrorReporting:(CDVInvokedUrlCommand*)command {
    BOOL enable = [[command.arguments objectAtIndex:0] boolValue];

    [self.prefs setBool:enable forKey:@"errorReportingEnabled"];
    [self.prefs synchronize];

    NSString *message = enable ? @"Error reporting enabled" : @"Error reporting disabled";
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                messageAsString:message];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)reportError:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate runInBackground:^{
        if (![self isInitialized]) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                        messageAsString:@"Plugin not initialized"];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            return;
        }

        BOOL enabled = [self.prefs boolForKey:@"errorReportingEnabled"];
        if (!enabled) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                        messageAsString:@"Error reporting is disabled"];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            return;
        }

        @try {
            NSString *message = [command.arguments objectAtIndex:0];
            NSString *stack = [command.arguments objectAtIndex:1];

            [self.updateManager reportErrorWithMessage:message stack:stack];

            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                        messageAsString:@"Error reported"];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];

        } @catch (NSException *exception) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                        messageAsString:exception.reason];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        }
    }];
}

- (void)getStatus:(CDVInvokedUrlCommand*)command {
    NSDictionary *status = @{
        @"initialized": @([self isInitialized]),
        @"currentVersion": [self.prefs stringForKey:@"currentVersion"] ?: @"base",
        @"errorReportingEnabled": @([self.prefs boolForKey:@"errorReportingEnabled"]),
        @"lastCheckTime": @([self.prefs doubleForKey:@"lastCheckTime"])
    };

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsDictionary:status];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)resetToBase:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate runInBackground:^{
        @try {
            [self.updateManager resetToBase];

            [self.prefs setObject:@"base" forKey:@"currentVersion"];
            [self.prefs synchronize];

            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                        messageAsString:@"Reset to base version"];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];

        } @catch (NSException *exception) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                        messageAsString:exception.reason];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        }
    }];
}

- (BOOL)isInitialized {
    return [self.prefs boolForKey:@"initialized"];
}

@end
