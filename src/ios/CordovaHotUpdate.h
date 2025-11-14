//
//  CordovaHotUpdate.h
//  Cordova Hot Update Plugin
//

#import <Cordova/CDVPlugin.h>

@interface CordovaHotUpdate : CDVPlugin

- (void)initialize:(CDVInvokedUrlCommand*)command;
- (void)checkForUpdate:(CDVInvokedUrlCommand*)command;
- (void)applyUpdate:(CDVInvokedUrlCommand*)command;
- (void)getCurrentVersion:(CDVInvokedUrlCommand*)command;
- (void)enableErrorReporting:(CDVInvokedUrlCommand*)command;
- (void)reportError:(CDVInvokedUrlCommand*)command;
- (void)getStatus:(CDVInvokedUrlCommand*)command;
- (void)resetToBase:(CDVInvokedUrlCommand*)command;

@end
