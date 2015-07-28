//
//  TCPlugin.h
//  Twilio Client plugin for PhoneGap / Cordova
//
//  Copyright 2012 Stevie Graham.
//


#import "TCPlugin.h"
#import  <AVFoundation/AVFoundation.h>
#import "NBPhoneNumberUtil.h"

@interface TCPlugin() {
    TCDevice     *_device;
    TCConnection *_connection;
    NSString     *_callback;
}

@property(nonatomic, strong) TCDevice     *device;
@property(nonatomic, strong) NSString     *callback;
@property(atomic, strong)    TCConnection *connection;
@property(atomic, strong)    UILocalNotification *ringNotification;
@property (atomic, strong) UILocalNotification *callNotification;
-(void)javascriptCallback:(NSString *)event;
-(void)javascriptCallback:(NSString *)event withArguments:(NSDictionary *)arguments;
-(void)javascriptErrorback:(NSError *)error;

@end

@implementation TCPlugin

@synthesize device     = _device;
@synthesize callback   = _callback;
@synthesize connection = _connection;
@synthesize ringNotification = _ringNotification;

- (void)pluginInitialize {
    [self getTwilioToken];
}

#pragma mark device delegate method

-(void)device:(TCDevice *)device didStopListeningForIncomingConnections:(NSError *)error {
    [[NSUserDefaults standardUserDefaults] setObject:nil forKey:@"TwilioToken"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self getTwilioToken];
    [self javascriptErrorback:error];
}

-(void)device:(TCDevice *)device didReceiveIncomingConnection:(TCConnection *)connection {
    self.callNotification = [[UILocalNotification alloc] init];
    if (self.callNotification == nil)
            return;
    self.callNotification.fireDate = [NSDate date];

    NSString *phone = connection.parameters[@"From"];
    phone = [self fixWierdPhoneNumber:phone];

    NSString *incoming = [[NSUserDefaults standardUserDefaults] objectForKey:@"TCIncomingText"];
    NSString *incomingText = [incoming stringByReplacingOccurrencesOfString:@"%phone%" withString:phone];

    self.callNotification.alertBody = incomingText;
    self.callNotification.userInfo = @{ @"info" : @"???" };
    [[UIApplication sharedApplication] scheduleLocalNotification:self.callNotification];
    self.connection = connection;
    self.connection.delegate = self;
    [self javascriptCallback:@"onincoming"];
}

- (NSString*)fixWierdPhoneNumber:(NSString*)phone {
    NSRange range = [phone rangeOfString:@"747"];
    if (range.location == 0) {
        phone = [phone stringByReplacingCharactersInRange:range withString:@""];
    } else {
        // keep phone as is.
    }
    range = [phone rangeOfString:@"+"];
    if (range.location == 0) {
        phone = [phone stringByReplacingCharactersInRange:range withString:@""];
    }
    return phone;
}


-(void)device:(TCDevice *)device didReceivePresenceUpdate:(TCPresenceEvent *)presenceEvent {
    NSString *available = [NSString stringWithFormat:@"%d", presenceEvent.isAvailable];
    NSDictionary *object = [NSDictionary dictionaryWithObjectsAndKeys:presenceEvent.name, @"from", available, @"available", nil];
    [self javascriptCallback:@"onpresence" withArguments:object];
}

-(void)deviceDidStartListeningForIncomingConnections:(TCDevice *)device {
    // What to do here? The JS library doesn't have an event for this.
}



- (void)getTwilioToken {
    NSString *oldToken = [[NSUserDefaults standardUserDefaults] objectForKey:@"TwilioToken"];
    if (oldToken != nil) {
        [self setupDeviceWithToken:oldToken];
        return;
    }

    NSString *accountUUID = [[NSUserDefaults standardUserDefaults] objectForKey:@"TCAccountUUID"]; //trapit
    NSString *sessionToken = [[NSUserDefaults standardUserDefaults] objectForKey:@"TCSessionToken"]; //whatever
    NSString *serverURL = [[NSUserDefaults standardUserDefaults] objectForKey:@"TCURL"];

    //Check if plugin has been setup.
    if (accountUUID == nil) {
        return;
    }

    NSString *dataUrl = [NSString stringWithFormat:@"%@capability-token?account_session__token=%@&account_session__account__info__uuid=%@", serverURL, sessionToken, accountUUID];
    NSURL *url = [NSURL URLWithString:dataUrl];

    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data != nil) {
        NSDictionary *sipSession = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];

        NSString *token = sipSession[@"sip_auth"][@"password"];

        if (token.length > 0) {
            NSLog(@"Got new Token: %@", token);
            [[NSUserDefaults standardUserDefaults] setObject:token forKey:@"TwilioToken"];
            [self setupDeviceWithToken:token];
        }
    }


}

- (void)setupDeviceWithToken:(NSString*)token {
    if (self.device == nil) {
        NSLog(@"Creating device");
        self.device = [[TCDevice alloc] initWithCapabilityToken:token delegate:self];
    } else {
        NSLog(@"Device exists");
        [self.device updateCapabilityToken:token];
    }
}

- (void)setupDeviceWithAccountUUID:(NSString*)accountUUID sessionToken:(NSString*)sessionToken serverURL:(NSString*)serverURL {
    [[NSUserDefaults standardUserDefaults] setObject:accountUUID forKey:@"TCAccountUUID"];
    [[NSUserDefaults standardUserDefaults] setObject:sessionToken forKey:@"TCSessionToken"];
    [[NSUserDefaults standardUserDefaults] setObject:serverURL forKey:@"TCURL"];
    [self getTwilioToken];
}


# pragma mark connection delegate methods

-(void)connection:(TCConnection*)connection didFailWithError:(NSError*)error {
    [self javascriptErrorback:error];
}

-(void)connectionDidStartConnecting:(TCConnection*)connection {
    self.connection = connection;
    // What to do here? The JS library doesn't have an event for connection negotiation.
}

-(void)connectionDidConnect:(TCConnection*)connection {
    self.callNotification = nil;
    self.connection = connection;
    [self javascriptCallback:@"onconnect"];
    if([connection isIncoming]) [self javascriptCallback:@"onaccept"];
}

-(void)connectionDidDisconnect:(TCConnection*)connection {

    if (self.callNotification != nil) {
        [[UIApplication sharedApplication] cancelLocalNotification:self.callNotification];
        self.callNotification = [[UILocalNotification alloc] init];
        self.callNotification.fireDate = [NSDate date];

        NSString *phone = connection.parameters[@"From"];
        phone = [self fixWierdPhoneNumber:phone];

        NSString *missed = [[NSUserDefaults standardUserDefaults] objectForKey:@"TCMissedText"];
        NSString *missedText = [missed stringByReplacingOccurrencesOfString:@"%phone%" withString:phone];

        self.callNotification.alertBody = missedText;
        self.callNotification.userInfo = @{ @"info" : @"???" };
        [[UIApplication sharedApplication] scheduleLocalNotification:self.callNotification];

        self.callNotification = nil;
    }

    self.connection = connection;
    [self javascriptCallback:@"ondevicedisconnect"];
    [self javascriptCallback:@"onconnectiondisconnect"];
}

# pragma mark javascript device mapper methods

-(void)deviceSetup:(CDVInvokedUrlCommand*)command {
    self.callback = command.callbackId;
    self.device = [[TCDevice alloc] initWithCapabilityToken:[command.arguments objectAtIndex:0] delegate:self];

    // Disable sounds. was getting EXC_BAD_ACCESS
    //self.device.incomingSoundEnabled   = NO;
    //self.device.outgoingSoundEnabled   = NO;
    //self.device.disconnectSoundEnabled = NO;

    // Local notification setup
    UIUserNotificationType types = UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert;

    UIUserNotificationSettings *mySettings = [UIUserNotificationSettings settingsForTypes:types categories:nil];

    [[UIApplication sharedApplication] registerUserNotificationSettings:mySettings];

    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(deviceStatusEvent) userInfo:nil repeats:NO];
}

-(void)deviceSetupWithAccountSession:(CDVInvokedUrlCommand*)command {
  self.callback = command.callbackId;

  [self setupDeviceWithAccountUUID:[command.arguments objectAtIndex:0] sessionToken:[command.arguments objectAtIndex:1] serverURL:[command.arguments objectAtIndex:2]];

  // Disable sounds. was getting EXC_BAD_ACCESS
  //self.device.incomingSoundEnabled   = NO;
  //self.device.outgoingSoundEnabled   = NO;
  //self.device.disconnectSoundEnabled = NO;

  // Local notification setup
    if ([[[UIDevice currentDevice] systemVersion] floatValue] > 8.0f) {

        UIUserNotificationType types = UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert;

        UIUserNotificationSettings *mySettings = [UIUserNotificationSettings settingsForTypes:types categories:nil];

        [[UIApplication sharedApplication] registerUserNotificationSettings:mySettings];
    }

  [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(deviceStatusEvent) userInfo:nil repeats:NO];
}

-(void)openAppSettings {
    if (&UIApplicationOpenSettingsURLString != NULL) {
        NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        [[UIApplication sharedApplication] openURL:url];
    }
    else {
        // Present some dialog telling the user to open the settings app.
    }
}

-(void)deviceStatusEvent {
    switch ([self.device state]) {
        case TCDeviceStateReady:
            [self javascriptCallback:@"onready"];
            NSLog(@"State: Ready");
            break;

        case TCDeviceStateOffline:
            [self javascriptCallback:@"onoffline"];
            NSLog(@"State: Offline");
            break;

        default:
            break;
    }
}

-(void)connect:(CDVInvokedUrlCommand*)command {
    [self.device connect:[command.arguments objectAtIndex:0] delegate:self];
}

-(void)disconnectAll:(CDVInvokedUrlCommand*)command {
    [self.device disconnectAll];
}

-(void)deviceStatus:(CDVInvokedUrlCommand*)command {
    NSString *state;
    switch ([self.device state]) {
        case TCDeviceStateBusy:
            state = @"busy";
            break;

        case TCDeviceStateReady:
            state = @"ready";
            break;

        case TCDeviceStateOffline:
            state = @"offline";
            break;

        default:
            break;
    }

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:state];
    [self performSelectorOnMainThread:@selector(writeJavascript:) withObject:[result toSuccessCallbackString:command.callbackId] waitUntilDone:NO];
}


# pragma mark javascript connection mapper methods

-(void)reset:(CDVInvokedUrlCommand*)command {
    [[NSUserDefaults standardUserDefaults] setObject:nil forKey:@"TCAccountUUID"];
    [[NSUserDefaults standardUserDefaults] setObject:nil forKey:@"TCSessionToken"];

    [self.device disconnectAll];
    [self.device setDelegate:nil];
    self.device = nil;
}

-(void)acceptConnection:(CDVInvokedUrlCommand*)command {
    [self.connection accept];
}

-(void)disconnectConnection:(CDVInvokedUrlCommand*)command {
    [self.connection disconnect];
}

-(void)rejectConnection:(CDVInvokedUrlCommand*)command {
    [self.connection reject];
}

-(void)muteConnection:(CDVInvokedUrlCommand*)command {
    if(self.connection.isMuted) {
        self.connection.muted = NO;
    } else {
        self.connection.muted = YES;
    }
}

-(void)sendDigits:(CDVInvokedUrlCommand*)command {
    [self.connection sendDigits:[command.arguments objectAtIndex:0]];
}

-(void)connectionStatus:(CDVInvokedUrlCommand*)command {
    NSString *state;
    switch ([self.connection state]) {
        case TCConnectionStateConnected:
            state = @"open";
            break;

        case TCConnectionStateConnecting:
            state = @"connecting";
            break;

        case TCConnectionStatePending:
            state = @"pending";
            break;

        case TCConnectionStateDisconnected:
            state = @"closed";

        default:
            break;
    }

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:state];
    [self performSelectorOnMainThread:@selector(writeJavascript:) withObject:[result toSuccessCallbackString:command.callbackId] waitUntilDone:NO];
}

-(void)connectionParameters:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[self.connection parameters]];
    [self performSelectorOnMainThread:@selector(writeJavascript:) withObject:[result toSuccessCallbackString:command.callbackId] waitUntilDone:NO];
}


-(void)showNotification:(CDVInvokedUrlCommand*)command {
    @try {
        [[UIApplication sharedApplication] cancelAllLocalNotifications];
    }
    @catch(NSException *exception) {
        NSLog(@"Couldn't Cancel Notification");
    }

    NSString *alertBody = [command.arguments objectAtIndex:0];

    NSString *ringSound = @"incoming.wav";
    if([command.arguments count] == 2) {
        ringSound = [command.arguments objectAtIndex:1];
    }

    _ringNotification = [[UILocalNotification alloc] init];
    _ringNotification.alertBody = alertBody;
    _ringNotification.alertAction = @"Answer";
    _ringNotification.soundName = ringSound;
    _ringNotification.fireDate = [NSDate date];
    [[UIApplication sharedApplication] scheduleLocalNotification:_ringNotification];

}

-(void)cancelNotification:(CDVInvokedUrlCommand*)command {
    [[UIApplication sharedApplication] cancelLocalNotification:_ringNotification];
}

-(void)setSpeaker:(CDVInvokedUrlCommand*)command {
    NSString *mode = [command.arguments objectAtIndex:0];
    if([mode isEqual: @"on"]) {
        UInt32 audioRouteOverride = kAudioSessionOverrideAudioRoute_Speaker;
        AudioSessionSetProperty (
            kAudioSessionProperty_OverrideAudioRoute,
            sizeof (audioRouteOverride),
            &audioRouteOverride
        );
    }
    else {
        UInt32 audioRouteOverride = kAudioSessionOverrideAudioRoute_None;
        AudioSessionSetProperty (
            kAudioSessionProperty_OverrideAudioRoute,
            sizeof (audioRouteOverride),
            &audioRouteOverride
        );
    }
}

/**
  * Sets the text for notifications. Use %phone% to insert the formatted phone number into your string.
  */
-(void)setNotificationText:(CDVInvokedUrlCommand*)command {
  NSString *incomingText = [command.arguments objectAtIndex:0];
  NSString *missedText = [command.arguments objectAtIndex:1];

  [[NSUserDefaults standardUserDefaults] setObject:incomingText forKey:@"TCIncomingText"];
  [[NSUserDefaults standardUserDefaults] setObject:missedText forKey:@"TCMissedText"];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

# pragma mark private methods

-(void)javascriptCallback:(NSString *)event withArguments:(NSDictionary *)arguments {
    NSDictionary *options   = [NSDictionary dictionaryWithObjectsAndKeys:event, @"callback", arguments, @"arguments", nil];
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options];
    result.keepCallback     = [NSNumber numberWithBool:YES];

    [self performSelectorOnMainThread:@selector(writeJavascript:) withObject:[result toSuccessCallbackString:self.callback] waitUntilDone:NO];
}

-(void)javascriptCallback:(NSString *)event {
    [self javascriptCallback:event withArguments:nil];
}

-(void)javascriptErrorback:(NSError *)error {
    NSDictionary *object    = [NSDictionary dictionaryWithObjectsAndKeys:[error localizedDescription], @"message", nil];
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:object];
    result.keepCallback     = [NSNumber numberWithBool:YES];

    [self performSelectorOnMainThread:@selector(writeJavascript:) withObject:[result toErrorCallbackString:self.callback] waitUntilDone:NO];
}

@end
