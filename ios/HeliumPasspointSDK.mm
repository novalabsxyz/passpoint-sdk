#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(HeliumPasspointSDK, NSObject)

RCT_EXTERN_METHOD(configure:(NSString *)apiKey
                  endpoint:(NSString *)endpoint
                  eapType:(nonnull NSNumber *)eapType
                  serverCaCertPem:(NSString *)serverCaCertPem
                  keychainAccessGroup:(NSString *)keychainAccessGroup)

RCT_EXTERN_METHOD(install:(NSString *)userIdentifier
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(isInstalled:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getCertificateInfo:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(debug:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(revoke:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

@end
