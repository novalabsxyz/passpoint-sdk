#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(HeliumPasspointSDK, NSObject)

RCT_EXTERN_METHOD(configure:(NSString *)apiKey
                  baseUrl:(NSString *)baseUrl
                  eapType:(nonnull NSNumber *)eapType
                  serverCaCertPem:(NSString * _Nullable)serverCaCertPem
                  keychainAccessGroup:(NSString * _Nullable)keychainAccessGroup
                  presetId:(NSString * _Nullable)presetId)

RCT_EXTERN_METHOD(install:(NSString *)subscriberId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(isInstalled:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getCertificateInfo:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getRemoteStatus:(NSString *)subscriberId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(debug:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(remove:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

@end
