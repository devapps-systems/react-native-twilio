#import "RNTwilio.h"
#import <React/RCTAsyncLocalStorage.h>


static NSString *const StatePending = @"PENDING";
static NSString *const StateConnecting = @"CONNECTING";
static NSString *const StateConnected = @"CONNECTED";
static NSString *const StateRinging = @"RINGING";
static NSString *const StateReconnecting = @"RECONNECTING";
static NSString *const StateDisconnected = @"DISCONNECTED";

static NSString *const PUSH_TOKEN = @"PUSH_TOKEN";
static NSString *const TWILIO_ACCESS_TOKEN = @"TWILIO_ACCESS_TOKEN";
static NSString *const FREEDOMSOFT_ACCESS_TOKEN = @"FREEDOMSOFT_ACCESS_TOKEN";
static NSString *const BASE_URL = @"BASE_URL";

@interface RNTwilio()<TVOCallDelegate, TVONotificationDelegate, CXProviderDelegate, PKPushRegistryDelegate>

@property (nonatomic, strong) TVOCall *call;
@property (nonatomic, strong) TVOCallInvite *callInvite;

@property (nonatomic, weak) id<PKPushRegistryDelegate> pushKitEventDelegate;
@property (nonatomic, strong) PKPushRegistry *voipRegistry;

@end

@implementation RNTwilio {
    NSString* accessToken;
    NSString* _deviceToken;
    NSDictionary *callParams;
    bool _hasListeners;
}

RCT_EXPORT_MODULE()

-(NSArray<NSString *> *)supportedEvents
{
    return @[@"deviceRegistered",
             @"deviceNotRegistered",
             @"connectionDidConnect",
             @"connectionDidDisconnect",
             @"connectionDidFail",
             @"connectionDidStartRinging",
             @"connectionIsReconnecting",
             @"connectionDidReconnect",
             @"incomingCall",
             @"incomingCallCancelled",
             @"callWasRejected"];
}

// Will be called when this module's first listener is added.
-(void)startObserving {
    _hasListeners = YES;
}

// Will be called when this module's last listener is removed, or on dealloc.
-(void)stopObserving {
    _hasListeners = NO;
}

-(void)sendEvent:(NSString*)eventName eventBody:(id)body
{
    if (_hasListeners) {
        [self sendEventWithName:eventName body:body];
    }
}

RCT_EXPORT_METHOD(logout) {
    NSData *token = [[NSUserDefaults standardUserDefaults] valueForKey:PUSH_TOKEN];
    [TwilioVoice unregisterWithAccessToken:accessToken deviceTokenData:token completion:^(NSError * _Nullable error) {
        if(error) {
            NSLog(@"Couldn't unregistered device from TWilio.");
        } else {
            NSLog(@"Successfullly unregistered device from TWilio.");
        }
    }];
}
                  
//==============================================
// 1.b initializeWithTokenAndBaseURL
//==============================================
RCT_EXPORT_METHOD(initializeWithTokenAndBaseURL:(NSString *)twilioToken :(NSString *)freedomSoftAccessToken :(NSString *)baseURL resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if ([twilioToken isEqualToString:@""]) {
        reject(@"400", @"The token can't be blank, please try again.", nil);
        return;
    }

    if ([baseURL isEqualToString:@""]) {
        reject(@"400", @"The base url can't be blank, please try again.", nil);
        return;
    }
    
    [[NSUserDefaults standardUserDefaults] setValue:freedomSoftAccessToken forKey:FREEDOMSOFT_ACCESS_TOKEN];
    [[NSUserDefaults standardUserDefaults] setValue:baseURL forKey:BASE_URL];
    
    if (![self checkRecordPermission]) {
        [self requestRecordPermission:^(BOOL granted) {
            if (!granted) {
                reject(@"400", @"The microphone permission is required for the initialization", nil);
            } else {
                [self registerForCallInvite];
                self->accessToken = twilioToken;
                [self commonInitialization];
                resolve(@{@"initialized": @true});
            }
        }];
    } else {
        [self registerForCallInvite];
        accessToken = twilioToken;
        [self commonInitialization];
        resolve(@{@"initialized": @true});
    }
    
}

RCT_EXPORT_METHOD(unregisterDevice:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSData *token = [[NSUserDefaults standardUserDefaults] valueForKey:PUSH_TOKEN];
    [TwilioVoice unregisterWithAccessToken:accessToken deviceTokenData:token completion:^(NSError * _Nullable error) {
        if(error) {
            NSLog(@"Couldn't unregistered device from TWilio.");
            resolve(@{@"status": @"Couldn't unregistered device from TWilio."});
        } else {
            NSLog(@"Successfullly unregistered device from TWilio.");
            resolve(@{@"status": @"Successfullly unregistered device from TWilio."});
        }
    }];
}

-(void) commonInitialization {
    CXProviderConfiguration *configuration = [[CXProviderConfiguration alloc] initWithLocalizedName:@"FreedomSoft"];
    configuration.maximumCallGroups = 1;
    configuration.maximumCallsPerCallGroup = 1;
    
    if (self.callKitProvider) {
        [self.callKitProvider invalidate];
    }
    
    self.callKitProvider = [[CXProvider alloc] initWithConfiguration:configuration];
    [self.callKitProvider setDelegate:self queue:nil];
    
    self.callKitCallController = [[CXCallController alloc] init];
    self.audioDevice = [TVODefaultAudioDevice audioDevice];
    TwilioVoice.audioDevice = self.audioDevice;
    TwilioVoice.logLevel = TVOLogLevelAll;
    self.activeCallInvites = [NSMutableDictionary dictionary];
    self.activeCalls = [NSMutableDictionary dictionary];
    self.playCustomRingback = NO;
    
    self.pushKitEventDelegate = self;
    [self initializePushKit];
    
}

- (void)initializePushKit {
    self.voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    self.voipRegistry.delegate = self;
    self.voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

- (void)dealloc {
    if (self.callKitProvider) {
        [self.callKitProvider invalidate];
    }
}

//=======================
// 4. makePhoneCall
//=======================
RCT_EXPORT_METHOD(makePhoneCall:(NSDictionary *)params)
{
    if (self.call && self.call.state == TVOCallStateConnected) {
        [self.call disconnect];
        [self.activeCall disconnect];
    } else {
        callParams = params;
        TVOConnectOptions *connectOptions = [TVOConnectOptions optionsWithAccessToken:accessToken block:^(TVOConnectOptionsBuilder * _Nonnull builder) {
            builder.params = params;
            builder.uuid = [NSUUID UUID];
        }];
        self.call = [TwilioVoice connectWithOptions:connectOptions delegate:self];
    }
}

//========================
// 7. disconnectActiveCall
//========================
RCT_EXPORT_METHOD(disconnectActiveCall)
{
    if (self.call) {
        [self.call disconnect];
    }
}

RCT_EXPORT_METHOD(getActiveCall:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.call) {
       resolve([self paramsForCall:self.call]);
    } else {
        reject(@"400", @"There is no active call", nil);
    }
}

//========================
// 5. acceptIncomingCall
//========================
RCT_EXPORT_METHOD(acceptIncomingCall)
{
    if (self.callInvite) {
        [self.callInvite acceptWithDelegate:self];
    }
}

//================================================
// 6. rejectIncomingCall, 3. callWasRejected
//================================================
RCT_EXPORT_METHOD(rejectIncomingCall)
{
    if (self.callInvite) {
        [self.callInvite reject];
        [self sendEvent:@"callWasRejected" eventBody:@{}];
    }
}

RCT_EXPORT_METHOD(setSpeakerPhone:(BOOL)isSpeaker)
{
    NSError *error = nil;
    if (isSpeaker) {
        if (![[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker
                                                                error:&error]) {
            NSLog(@"Turn on speaker error: %@", [error localizedDescription]);
        }
    } else {
        if (![[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone
                                                                error:&error]) {
            NSLog(@"Turn off speaker error: %@", [error localizedDescription]);
        }
    }
}

RCT_EXPORT_METHOD(sendDtmf:(NSString *)dtmf)
{
    if(self.call != nil) {
        [self.call sendDigits:dtmf];
    }
}

RCT_EXPORT_METHOD(setMute:(BOOL) shouldMute)
{
    if(self.call != nil) {
        [self.call setMuted:shouldMute];
    }
}



- (BOOL)checkRecordPermission
{
    AVAudioSessionRecordPermission permissionStatus = [[AVAudioSession sharedInstance] recordPermission];
    return permissionStatus == AVAudioSessionRecordPermissionGranted;
}

- (void)requestRecordPermission:(void(^)(BOOL))completion
{
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        completion(granted);
    }];
}

- (NSMutableDictionary *)paramsForCall:(TVOCall *)call
{
    NSMutableDictionary *callParams = [[NSMutableDictionary alloc] init];
    if(call != nil) {
        [callParams setObject:call.sid forKey:@"call_sid"];
        if (call.state == TVOCallStateConnecting) {
            [callParams setObject:StateConnecting forKey:@"call_state"];
        } else if (call.state == TVOCallStateConnected) {
            [callParams setObject:StateConnected forKey:@"call_state"];
        } else if (call.state == TVOCallStateRinging) {
            [callParams setObject:StateRinging forKey:@"call_state"];
        } else if (call.state == TVOCallStateReconnecting) {
            [callParams setObject:StateReconnecting forKey:@"call_state"];
        } else if (call.state == TVOCallStateDisconnected) {
            [callParams setObject:StateDisconnected forKey:@"call_state"];
        }
        
        if (call.from) {
            [callParams setObject:call.from forKey:@"call_from"];
        }
        if (call.to) {
            [callParams setObject:call.to forKey:@"call_to"];
        }
    }
    
    return callParams;
}


- (NSMutableDictionary *)paramsForError:(NSError *)error {
    NSMutableDictionary *params = [self paramsForCall:self.call];
    
    if (error) {
        NSMutableDictionary *errorParams = [[NSMutableDictionary alloc] init];
        if (error.code) {
            [errorParams setObject:[@([error code]) stringValue] forKey:@"code"];
        }
        if (error.domain) {
            [errorParams setObject:[error domain] forKey:@"domain"];
        }
        if (error.localizedDescription) {
            [errorParams setObject:[error localizedDescription] forKey:@"message"];
        }
        if (error.localizedFailureReason) {
            [errorParams setObject:[error localizedFailureReason] forKey:@"reason"];
        }
        [params setObject:errorParams forKey:@"error"];
    }
    return params;
}

- (void)registerForCallInvite
{
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    self.voipRegistry = [[PKPushRegistry alloc] initWithQueue:mainQueue];
    self.voipRegistry.delegate = self;
    self.voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

#pragma mark - TVOCallDelegate methods
- (void)call:(nonnull TVOCall *)call didDisconnectWithError:(nullable NSError *)error
{
    [UIDevice currentDevice].proximityMonitoringEnabled = NO;
    
    if (!self.userInitiatedDisconnect) {
        CXCallEndedReason reason = CXCallEndedReasonRemoteEnded;
        if (error) {
            reason = CXCallEndedReasonFailed;
        }
        
        [self.callKitProvider reportCallWithUUID:call.uuid endedAtDate:[NSDate date] reason:reason];
    }

    [self callDisconnected:call];
    
    NSMutableDictionary *params = [self paramsForError:error];
    [self sendEvent:@"connectionDidDisconnect" eventBody:params];
    self.call = nil;
}

- (void)callDisconnected:(TVOCall *)call {
    if ([call isEqual:self.activeCall]) {
        self.activeCall = nil;
    }
    [self.activeCalls removeObjectForKey:call.uuid.UUIDString];
    
    self.userInitiatedDisconnect = NO;
}

- (void)call:(nonnull TVOCall *)call didFailToConnectWithError:(nonnull NSError *)error
{
    [UIDevice currentDevice].proximityMonitoringEnabled = NO;
    NSMutableDictionary *params = [self paramsForError:error];
    [self sendEvent:@"connectionDidFail" eventBody:params];
    self.call = nil;
}

//========================
// 2. connectionDidConnect
//========================
- (void)callDidConnect:(nonnull TVOCall *)call
{
    self.call = call;
    [UIDevice currentDevice].proximityMonitoringEnabled = YES;
    if (self.callInvite) {
        self.callInvite = nil;
    }
    NSMutableDictionary *paramsForCall = [self paramsForCall:call];
    [self sendEvent:@"connectionDidConnect" eventBody:paramsForCall];
}

- (void)callDidStartRinging:(nonnull TVOCall *)call
{
    self.call = call;
    NSMutableDictionary *paramsForCall = [self paramsForCall:call];
    [self sendEvent:@"connectionDidStartRinging" eventBody:paramsForCall];
}

- (void)call:(nonnull TVOCall *)call isReconnectingWithError:(nonnull NSError *)error
{
    self.call = call;
    NSMutableDictionary *paramsForCall = [self paramsForError:error];
    [self sendEvent:@"connectionIsReconnecting" eventBody:paramsForCall];
}

- (void)callDidReconnect:(nonnull TVOCall *)call
{
    [UIDevice currentDevice].proximityMonitoringEnabled = YES;
    self.call = call;
    if (self.callInvite) {
        self.callInvite = nil;
    }
    NSMutableDictionary *paramsForCall = [self paramsForCall:call];
    [self sendEvent:@"connectionDidReconnect" eventBody:paramsForCall];
}

#pragma mark - PKPushRegistryDelegate
- (void)pushRegistry:(nonnull PKPushRegistry *)registry didUpdatePushCredentials:(nonnull PKPushCredentials *)pushCredentials forType:(nonnull PKPushType)type
{
    if ([type isEqualToString:PKPushTypeVoIP]) {
        _deviceToken = pushCredentials.token.description;
        if (accessToken && _deviceToken) {
            [[NSUserDefaults standardUserDefaults] setValue:pushCredentials.token forKey:PUSH_TOKEN];
            [TwilioVoice registerWithAccessToken:accessToken deviceTokenData:pushCredentials.token completion:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"An error occurred while registering: %@", error.localizedDescription);
                    NSMutableDictionary *errParams = [self paramsForError:error];
                    [self sendEvent:@"deviceNotRegistered" eventBody:errParams];
                } else {
                    NSLog(@"Successfully registered for VoIP push notifications.");
                }
            }];
        }
    }
}

- (NSString *)stringWithDeviceToken:(NSData *)deviceToken {
    const char *data = [deviceToken bytes];
    NSMutableString *token = [NSMutableString string];

    for (NSUInteger i = 0; i < [deviceToken length]; i++) {
        [token appendFormat:@"%02.2hhX", data[i]];
    }

    return [token copy];
}

- (void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(PKPushType)type
{
    if ([type isEqualToString:PKPushTypeVoIP]) {
        NSData *token = [[NSUserDefaults standardUserDefaults] valueForKey:PUSH_TOKEN];
        [TwilioVoice unregisterWithAccessToken:accessToken deviceTokenData:token completion:^(NSError * _Nullable error) {
            if(error) {
                NSLog(@"Couldn't unregistered device from TWilio.");
            } else {
                NSLog(@"Successfullly unregistered device from TWilio.");
                [self sendEvent:@"deviceNotRegistered" eventBody:@{}];
            }
        }];
    }
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(PKPushType)type withCompletionHandler:(void(^)(void))completion
{
    if ([type isEqualToString:PKPushTypeVoIP]) {
        dispatch_queue_t mainQueue = dispatch_get_main_queue();
        [TwilioVoice handleNotification:payload.dictionaryPayload delegate:self delegateQueue:mainQueue];
        completion();
    }
}

// deprecated for iOS 8 ~ iOS 11
- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(PKPushType)type
{
    if ([type isEqualToString:PKPushTypeVoIP]) {
        dispatch_queue_t mainQueue = dispatch_get_main_queue();
        
        NSMutableDictionary *updatedPayload = [[NSMutableDictionary alloc] initWithDictionary:payload.dictionaryPayload];
        updatedPayload[@"twi_message_type"] = @"twilio.voice.call";
        updatedPayload[@"twi_call_sid"] = updatedPayload[@"CallSid"];
        updatedPayload[@"twi_to"] = updatedPayload[@"To"];
        updatedPayload[@"To"] = updatedPayload[@"To"];
        updatedPayload[@"From"] = updatedPayload[@"From"];
        updatedPayload[@"twi_bridge_token"] = updatedPayload[@"Token"];
        
        [TwilioVoice handleNotification:updatedPayload delegate:self delegateQueue:mainQueue];
    }
}

#pragma mark - TVONotificationDelegate
- (void)callInviteReceived:(TVOCallInvite *)callInvite {
    
    /**
     * Calling `[TwilioVoice handleNotification:delegate:]` will synchronously process your notification payload and
     * provide you a `TVOCallInvite` object. Report the incoming call to CallKit upon receiving this callback.
     */

    NSLog(@"callInviteReceived:");
    
    NSString *from = @"Voice Bot";
    if (callInvite.from) {
        from = [callInvite.from stringByReplacingOccurrencesOfString:@"client:" withString:@""];
    }
    
    // Always report to CallKit
    [self reportIncomingCallFrom:from andcallInvite:callInvite];
    self.activeCallInvites[[callInvite.uuid UUIDString]] = callInvite;
    if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion < 13) {
        [self incomingPushHandled];
    }
    
    NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
    
    NSString *callSID = callInvite.callSid;
    NSString *callTo = callInvite.to;
    
    [params setObject:callSID forKey:@"call_sid"];
    [params setObject:from forKey:@"call_from"];
    [params setObject:callTo forKey:@"call_to"];
    NSDictionary<NSString *, NSString *> *customParams = callInvite.customParameters;
    NSArray<NSString *> *allKeys = [customParams allKeys];
    [allKeys enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [params setObject:[customParams objectForKey:obj] forKey:obj];
    }];
    
    [self sendEvent:@"incomingCall" eventBody:params];
}

#pragma mark - CallKit Actions
- (void)performStartCallActionWithUUID:(NSUUID *)uuid handle:(NSString *)handle {
    if (uuid == nil || handle == nil) {
        return;
    }

    CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:handle];
    CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:uuid handle:callHandle];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:startCallAction];

    [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
        if (error) {
            NSLog(@"StartCallAction transaction request failed: %@", [error localizedDescription]);
        } else {
            NSLog(@"StartCallAction transaction request successful");

            CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
            callUpdate.remoteHandle = callHandle;
            callUpdate.supportsDTMF = YES;
            callUpdate.supportsHolding = YES;
            callUpdate.supportsGrouping = NO;
            callUpdate.supportsUngrouping = NO;
            callUpdate.hasVideo = NO;

            [self.callKitProvider reportCallWithUUID:uuid updated:callUpdate];
        }
    }];
}

- (void)reportIncomingCallFrom:(NSString *) from andcallInvite:(TVOCallInvite *)callInvite {
    
    // 1.6.37
    CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:from];

    CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
    callUpdate.remoteHandle = callHandle;
    callUpdate.supportsDTMF = YES;
    [callUpdate setLocalizedCallerName:from];
    callUpdate.supportsHolding = YES;
    callUpdate.supportsGrouping = NO;
    callUpdate.supportsUngrouping = NO;
    callUpdate.hasVideo = NO;
    [self.callKitProvider reportNewIncomingCallWithUUID:callInvite.uuid update:callUpdate completion:^(NSError *error) {
        if (!error) {
            NSLog(@"Incoming call successfully reported.");
        }
        else {
            NSLog(@"Failed to report incoming call successfully: %@.", [error localizedDescription]);
        }
    }];
    
    NSString *baseURL = [[NSUserDefaults standardUserDefaults] valueForKey:BASE_URL];
    NSString *token = [[NSUserDefaults standardUserDefaults] valueForKey:FREEDOMSOFT_ACCESS_TOKEN];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/mobile/api/v1/calls/%@", baseURL, callInvite.callSid]]];
    [request setHTTPMethod:@"GET"];

    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfiguration.HTTPAdditionalHeaders = @{@"Authorization": [NSString stringWithFormat: @"Bearer %@", token] };
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if(error) {
            [self prepareCall:callInvite andReportWithName:from];
        } else {
            NSDictionary *callDetails = [NSJSONSerialization JSONObjectWithData:data options:NSASCIIStringEncoding error:&error];
            NSDictionary *call = [callDetails valueForKey:@"call"];
            NSString *callerName = [call valueForKey:@"name"];
            
            if(![callerName isEqualToString:@""]) {
                [self prepareCall:callInvite andReportWithName:callerName];
            } else {
                [self prepareCall:callInvite andReportWithName:from];
            }
        }
    }] resume];
}

-(void) prepareCall:(TVOCallInvite *)callInvite  andReportWithName:(NSString *) name {
    NSLog(@"*** prepareCall andReportWithName called ***");
    CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:name];

    CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
    callUpdate.remoteHandle = callHandle;
    callUpdate.supportsDTMF = YES;
    [callUpdate setLocalizedCallerName:name];
    callUpdate.supportsHolding = YES;
    callUpdate.supportsGrouping = NO;
    callUpdate.supportsUngrouping = NO;
    callUpdate.hasVideo = NO;
    
    [self.callKitProvider reportCallWithUUID:callInvite.uuid updated:callUpdate];
}

- (void)incomingPushHandled {
    if (self.incomingPushCompletionCallback) {
        self.incomingPushCompletionCallback();
        self.incomingPushCompletionCallback = nil;
    }
}

- (void)cancelledCallInviteReceived:(nonnull TVOCancelledCallInvite *)cancelledCallInvite error:(nonnull NSError *)error {
    NSLog(@"cancelledCallInviteReceived:");
    
    TVOCallInvite *callInvite;
    for (NSString *uuid in self.activeCallInvites) {
        TVOCallInvite *activeCallInvite = [self.activeCallInvites objectForKey:uuid];
        if ([cancelledCallInvite.callSid isEqualToString:activeCallInvite.callSid]) {
            callInvite = activeCallInvite;
            break;
        }
    }
    
    if (callInvite) {
        [self performEndCallActionWithUUID:callInvite.uuid];
    }
    
    self.callInvite = nil;
    NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
    [params setObject:cancelledCallInvite.callSid forKey:@"call_sid"];
    
    if (cancelledCallInvite.from) {
        [params setObject:cancelledCallInvite.from forKey:@"call_from"];
    }
    if (cancelledCallInvite.to) {
        [params setObject:cancelledCallInvite.to forKey:@"call_to"];
    }
    
    [self sendEvent:@"incomingCallCancelled" eventBody:params];
}

- (void)performEndCallActionWithUUID:(NSUUID *)uuid {
    CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:uuid];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];

    [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
        if (error) {
            NSLog(@"EndCallAction transaction request failed: %@", [error localizedDescription]);
        }
        else {
            NSLog(@"EndCallAction transaction request successful");
        }
    }];
}

- (void)performAnswerVoiceCallWithUUID:(NSUUID *)uuid
                            completion:(void(^)(BOOL success))completionHandler {
    TVOCallInvite *callInvite = self.activeCallInvites[uuid.UUIDString];
    NSAssert(callInvite, @"No CallInvite matches the UUID");
    
    TVOAcceptOptions *acceptOptions = [TVOAcceptOptions optionsWithCallInvite:callInvite block:^(TVOAcceptOptionsBuilder *builder) {
        builder.uuid = callInvite.uuid;
    }];

    TVOCall *call = [callInvite acceptWithOptions:acceptOptions delegate:self];

    if (!call) {
        completionHandler(NO);
    } else {
        self.callKitCompletionCallback = completionHandler;
        self.activeCall = call;
        self.activeCalls[call.uuid.UUIDString] = call;
    }

    [self.activeCallInvites removeObjectForKey:callInvite.uuid.UUIDString];
    
    if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion < 13) {
        [self incomingPushHandled];
    }
}

- (void)performVoiceCallWithUUID:(NSUUID *)uuid
                          client:(NSString *)client
                      completion:(void(^)(BOOL success))completionHandler {
    __weak typeof(self) weakSelf = self;
    TVOConnectOptions *connectOptions = [TVOConnectOptions optionsWithAccessToken:accessToken block:^(TVOConnectOptionsBuilder *builder) {
        __strong typeof(self) strongSelf = weakSelf;
        builder.params = strongSelf->callParams;
        builder.uuid = uuid;
    }];
    TVOCall *call = [TwilioVoice connectWithOptions:connectOptions delegate:self];
    if (call) {
        self.activeCall = call;
        self.activeCalls[call.uuid.UUIDString] = call;
    }
    self.callKitCompletionCallback = completionHandler;
}

#pragma mark - CXProviderDelegate
- (void)providerDidReset:(CXProvider *)provider {
    NSLog(@"providerDidReset:");
    self.audioDevice.enabled = YES;
}

- (void)providerDidBegin:(CXProvider *)provider {
    NSLog(@"providerDidBegin:");
}

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession {
    NSLog(@"provider:didActivateAudioSession:");
    self.audioDevice.enabled = YES;
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession *)audioSession {
    NSLog(@"provider:didDeactivateAudioSession:");
}

- (void)provider:(CXProvider *)provider timedOutPerformingAction:(CXAction *)action {
    NSLog(@"provider:timedOutPerformingAction:");
}

- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action {
    NSLog(@"provider:performStartCallAction:");

    self.audioDevice.enabled = NO;
    self.audioDevice.block();
    
    [self.callKitProvider reportOutgoingCallWithUUID:action.callUUID startedConnectingAtDate:[NSDate date]];
    
    __weak typeof(self) weakSelf = self;
    [self performVoiceCallWithUUID:action.callUUID client:nil completion:^(BOOL success) {
        __strong typeof(self) strongSelf = weakSelf;
        if (success) {
            NSLog(@"performVoiceCallWithUUID successful");
            [strongSelf.callKitProvider reportOutgoingCallWithUUID:action.callUUID connectedAtDate:[NSDate date]];
        } else {
            NSLog(@"performVoiceCallWithUUID failed");
        }
        [action fulfill];
    }];
}

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action {
    NSLog(@"provider:performAnswerCallAction:");
    
    self.audioDevice.enabled = NO;
    self.audioDevice.block();
    
    [self performAnswerVoiceCallWithUUID:action.callUUID completion:^(BOOL success) {
        if (success) {
            NSLog(@"performAnswerVoiceCallWithUUID successful");
        } else {
            NSLog(@"performAnswerVoiceCallWithUUID failed");
        }
    }];
    
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action {
    NSLog(@"provider:performEndCallAction:");
    
    TVOCallInvite *callInvite = self.activeCallInvites[action.callUUID.UUIDString];
    TVOCall *call = self.activeCalls[action.callUUID.UUIDString];

    if (callInvite) {
        [callInvite reject];
        [self.activeCallInvites removeObjectForKey:callInvite.uuid.UUIDString];
    } else if (call) {
        [call disconnect];
    } else {
        NSLog(@"Unknown UUID to perform end-call action with");
    }

    [action fulfill];
}

- (void)provider:(CXProvider *)provider performSetHeldCallAction:(CXSetHeldCallAction *)action {
    TVOCall *call = self.activeCalls[action.callUUID.UUIDString];
    if (call) {
        [call setOnHold:action.isOnHold];
        [action fulfill];
    } else {
        [action fail];
    }
}

- (void)provider:(CXProvider *)provider performSetMutedCallAction:(CXSetMutedCallAction *)action {
    TVOCall *call = self.activeCalls[action.callUUID.UUIDString];
    if (call) {
        [call setMuted:action.isMuted];
        [action fulfill];
    } else {
        [action fail];
    }
}

@end
