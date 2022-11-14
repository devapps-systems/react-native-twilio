#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
@import CallKit;
@import PushKit;
@import TwilioVoice;

@interface RNTwilio : RCTEventEmitter <RCTBridgeModule, PKPushRegistryDelegate>

@property (nonatomic, strong) void(^incomingPushCompletionCallback)(void);
@property (nonatomic, strong) void(^callKitCompletionCallback)(BOOL);
@property (nonatomic, strong) TVODefaultAudioDevice *audioDevice;
@property (nonatomic, strong) NSMutableDictionary *activeCallInvites;
@property (nonatomic, strong) NSMutableDictionary *activeCalls;

@property (nonatomic, strong) TVOCall *activeCall;

@property (nonatomic, strong) CXProvider *callKitProvider;
@property (nonatomic, strong) CXCallController *callKitCallController;
@property (nonatomic, assign) BOOL userInitiatedDisconnect;

@property (nonatomic, assign) BOOL playCustomRingback;
@property (nonatomic, strong) AVAudioPlayer *ringtonePlayer;

@end
