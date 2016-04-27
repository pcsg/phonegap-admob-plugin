#import "AdMobPlugin.h"
#import <GoogleMobileAds/GADExtras.h>
#import <GoogleMobileAds/GADAdSize.h>
#import <GoogleMobileAds/GADBannerView.h>
#import <GoogleMobileAds/GADInterstitial.h>

@interface AdMobPlugin ()

@property CGRect superViewFrame;
@property CGRect bannerViewFrame;
@property UIEdgeInsets webViewContentInsets;

@property GADAdSize adSize;

- (void)createGADBannerViewWithPubId:(NSString *)pubId
                          bannerType:(GADAdSize)adSize;
- (void)createGADInterstitialWithPubId:(NSString *)pubId;
- (void)requestAdWithTesting:(BOOL)isTesting
                      extras:(NSDictionary *)extraDict;
- (void)resizeViews;
- (GADAdSize)GADAdSizeFromString:(NSString *)string;
- (void)deviceOrientationChange:(NSNotification *)notification;

@end

@implementation AdMobPlugin

@synthesize bannerView = bannerView_;
@synthesize interstitial = interstitial_;

@synthesize superViewFrame, bannerViewFrame, webViewContentInsets, adSize;

#pragma mark Cordova JS bridge

- (CDVPlugin *)initWithWebView:(UIWebView *)theWebView {
    self = (AdMobPlugin *)[super initWithWebView:theWebView];

    if (self) {
        // These notifications are required for re-placing the ad on orientation
        // changes. Start listening for notifications here since we need to
        // translate the Smart Banner constants according to the orientation.
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(deviceOrientationChange:)
         name:UIDeviceOrientationDidChangeNotification
         object:nil];
        
        //watch for AGWebViewScrollViewContentInsetChanged notifications for this webview
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(webViewScrollViewContentInsetChanged:)
         name:@"AGWebViewScrollViewContentInsetChanged"
         object:theWebView];
        
        
        self.superViewFrame = self.webView.superview.frame;
        self.webViewContentInsets = [[[self webView] scrollView] contentInset];
    }

    return self;
}

// The javascript from the AdMob plugin calls this when createBannerView is
// invoked. This method parses the arguments passed in.
- (void)createBannerView:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult;
    NSDictionary *params = [command argumentAtIndex:0];
    NSString *callbackId = command.callbackId;
    NSString *adSizeString = [params objectForKey:@"adSize"];
    self.adSize = [self GADAdSizeFromString:adSizeString];
    positionAdAtTop_ = NO;

    // We don't need positionAtTop to be set, but we need values for adSize and
    // publisherId if we don't want to fail.
    if (![params objectForKey: @"publisherId"]) {
        // Call the error callback that was passed in through the javascript
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"AdMobPlugin:"
                        @"Invalid publisher Id"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];

        return;
    }

    if (GADAdSizeEqualToSize(adSize, kGADAdSizeInvalid)) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"AdMobPlugin:"
                        @"Invalid ad size"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];

        return;
    }

    if ([params objectForKey: @"positionAtTop"]) {
        positionAdAtTop_= [[params objectForKey: @"positionAtTop"] boolValue];
    }

    NSString *publisherId = [params objectForKey: @"publisherId"];

    [self createGADBannerViewWithPubId:publisherId
                            bannerType:adSize];

    // Call the success callback that was passed in through the javascript.
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

// The javascript from the AdMob plugin calls this when createInterstitialView is
// invoked. This method parses the arguments passed in.
- (void)createInterstitialView:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult;
    NSDictionary *params = [command argumentAtIndex:0];
    NSString *callbackId = command.callbackId;
    // We don't need positionAtTop to be set, but we need values for adSize and
    // publisherId if we don't want to fail.
    if (![params objectForKey: @"publisherId"]) {
        // Call the error callback that was passed in through the javascript
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"AdMobPlugin:"
                        @"Invalid publisher Id"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];

        return;
    }
    if ([params objectForKey: @"positionAtTop"]) {
        positionAdAtTop_= [[params objectForKey: @"positionAtTop"] boolValue];
    }

    NSString *publisherId = [params objectForKey: @"publisherId"];

    [self createGADInterstitialWithPubId:publisherId];

    // Call the success callback that was passed in through the javascript.
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void)requestAd:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult;
    NSDictionary *params = [command argumentAtIndex:0];
    NSString *callbackId = command.callbackId;
    NSDictionary *extrasDictionary = nil;

    if (!self.bannerView && !self.interstitial) {
        // Try to prevent requestAd from being called without createBannerView first
        // being called.
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"AdMobPlugin:"
                        @"No ad view exists"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];

        return;
    }

    if ([params objectForKey: @"extras"]) {
        extrasDictionary = [NSDictionary dictionaryWithDictionary:
                            [params objectForKey: @"extras"]];
    }

    BOOL isTesting = [[params objectForKey: @"isTesting"] boolValue];

    [self requestAdWithTesting:isTesting extras:extrasDictionary];

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void)killAd:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult;
    NSString *callbackId = command.callbackId;

    if(self.bannerView) {
        [[[self webView] scrollView] setContentInset:webViewContentInsets];
        [[[self webView] scrollView] setScrollIndicatorInsets:webViewContentInsets];

        [self.bannerView setDelegate:nil];
        [self.bannerView removeFromSuperview];
        self.bannerView = nil;

    } else if(self.interstitial){
        //[self.interstitial setDelegate:nil];
        //[self.interstitial removeFromSuperview];
        //self.interstitial = nil;

    } else {
        // Try to prevent requestAd from being called without createBannerView first
        // being called.
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"AdMobPlugin:"
                        @"No ad view exists"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];

        return;
    }

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (GADAdSize)GADAdSizeFromString:(NSString *)string {
    // Create a new alert object and set initial values.
    if ([string isEqualToString:@"BANNER"]) {
        return kGADAdSizeBanner;
    } else if ([string isEqualToString:@"IAB_MRECT"]) {
        return kGADAdSizeMediumRectangle;
    } else if ([string isEqualToString:@"IAB_BANNER"]) {
        return kGADAdSizeFullBanner;
    } else if ([string isEqualToString:@"IAB_LEADERBOARD"]) {
        return kGADAdSizeLeaderboard;
    } else if ([string isEqualToString:@"SMART_BANNER"]) {
        // Have to choose the right Smart Banner constant according to orientation.
        UIDeviceOrientation currentOrientation =
        [[UIDevice currentDevice] orientation];
        if (UIInterfaceOrientationIsPortrait(currentOrientation)) {
            return kGADAdSizeSmartBannerPortrait;
        }
        else {
            return kGADAdSizeSmartBannerLandscape;
        }
    } else {
        return kGADAdSizeInvalid;
    }
}

#pragma mark Ad Banner logic

- (void)createGADBannerViewWithPubId:(NSString *)pubId
                          bannerType:(GADAdSize)adSize {
    self.bannerView = [[GADBannerView alloc] initWithAdSize:adSize];
    self.bannerView.adUnitID = pubId;
    self.bannerView.delegate = self;
    self.bannerView.rootViewController = self.viewController;
    
    self.bannerViewFrame = self.bannerView.frame;
}

- (void)createGADInterstitialWithPubId:(NSString *)pubId {
    self.interstitial = [[GADInterstitial alloc] init];
    self.interstitial.adUnitID = pubId;
    self.interstitial.delegate = self;
}

- (void)requestAdWithTesting:(BOOL)isTesting extras:(NSDictionary *)extrasDict {
    GADRequest *request = [GADRequest request];

    if (isTesting) {
        // Make the request for a test ad. Put in an identifier for the simulator as
        // well as any devices you want to receive test ads.
        request.testDevices = [NSArray arrayWithObjects: GAD_SIMULATOR_ID,
         // TODO: Add your device test identifiers here. They are
         // printed to the console when the app is launched.
         nil];
    }

    if (extrasDict) {
        GADExtras *extras = [[GADExtras alloc] init];
        NSMutableDictionary *modifiedExtrasDict = [[NSMutableDictionary alloc] initWithDictionary:extrasDict];

        [modifiedExtrasDict removeObjectForKey:@"cordova"];
        [modifiedExtrasDict setValue:@"1" forKey:@"cordova"];

        extras.additionalParameters = modifiedExtrasDict;

        [request registerAdNetworkExtras:extras];
    }

    if(self.bannerView) {
        NSLog(@"%@", self.bannerView);

        [self.bannerView loadRequest:request];

        // Add the ad to the main container view, and resize the webview to make space for it.
        [self.webView.superview addSubview:self.bannerView];

        [self resizeViews];

    } else if(self.interstitial) {
        NSLog(@"%@", self.interstitial);

        [self.interstitial loadRequest:request];
    }
}

- (void)resizeViews {
    // If the banner hasn't been created yet, no need for resizing views.
    if (!self.bannerView) {
        return;
    }

    // If the ad is not showing or the ad is hidden, we don't want to resize anything.
    BOOL adIsShowing = [self.webView.superview.subviews containsObject:self.bannerView];
    if (!adIsShowing || self.bannerView.hidden) {
        return;
    }

    UIInterfaceOrientation currentOrientation = [[self viewController] interfaceOrientation];

    // Handle changing Smart Banner constants for the user.
    BOOL adIsSmartBannerPortrait = GADAdSizeEqualToSize(self.bannerView.adSize,
                                                        kGADAdSizeSmartBannerPortrait);
    BOOL adIsSmartBannerLandscape = GADAdSizeEqualToSize(self.bannerView.adSize,
                                                         kGADAdSizeSmartBannerLandscape);

    if (adIsSmartBannerPortrait && UIInterfaceOrientationIsLandscape(currentOrientation)) {
        self.bannerView.adSize = kGADAdSizeSmartBannerLandscape;

    } else if (adIsSmartBannerLandscape && UIInterfaceOrientationIsPortrait(currentOrientation)) {
        self.bannerView.adSize = kGADAdSizeSmartBannerPortrait;
    }
    
    if (positionAdAtTop_) {
        // Ad is on top of the webview

        // iOS7 top contentInset for the webview is the correct spot for banner view origin
        int oldWebViewContentInsetTop = self.webViewContentInsets.top;
        int newBannerViewY = self.superViewFrame.origin.y + oldWebViewContentInsetTop;

        self.bannerView.frame = CGRectMake(superViewFrame.origin.x,
                                           newBannerViewY,
                                           bannerViewFrame.size.width,
                                           bannerViewFrame.size.height);


        int newWebViewContentInsetTop = oldWebViewContentInsetTop + bannerViewFrame.size.height;
        UIEdgeInsets newWebViewInsets = UIEdgeInsetsMake(newWebViewContentInsetTop,
                                                         webViewContentInsets.left,
                                                         webViewContentInsets.bottom,
                                                         webViewContentInsets.right);

        [[[self webView] scrollView] setContentInset:newWebViewInsets];
        [[[self webView] scrollView] setScrollIndicatorInsets:newWebViewInsets];

    } else {
        // Ad is below the webview

        int oldWebViewContentInsetBottom = self.webViewContentInsets.bottom;
        int newBannerViewY = self.superViewFrame.size.height - oldWebViewContentInsetBottom - bannerViewFrame.size.height;
        
        self.bannerView.frame = CGRectMake(superViewFrame.origin.x,
                                           newBannerViewY,
                                           bannerViewFrame.size.width,
                                           bannerViewFrame.size.height);
        
        
        int newWebViewContentInsetBottom = oldWebViewContentInsetBottom + bannerViewFrame.size.height;
        UIEdgeInsets newWebViewInsets = UIEdgeInsetsMake(webViewContentInsets.top,
                                                         webViewContentInsets.left,
                                                         newWebViewContentInsetBottom,
                                                         webViewContentInsets.right);
        
        [[[self webView] scrollView] setContentInset:newWebViewInsets];
        [[[self webView] scrollView] setScrollIndicatorInsets:newWebViewInsets];
        
    }
}

- (void)deviceOrientationChange:(NSNotification *)notification {
    [self resizeViews];
}

- (void)webViewScrollViewContentInsetChanged:(NSNotification *)notification {
    self.webViewContentInsets = [[[self webView] scrollView] contentInset];
    [self resizeViews];
}

#pragma mark GADBannerViewDelegate implementation

- (void)adViewDidReceiveAd:(GADBannerView *)adView {
    NSLog(@"%s: Received ad successfully. adView.frame.size.height: %f", __PRETTY_FUNCTION__, adView.frame.size.height);
    
    //Hack to avoid the banner going full screen
    //Constraint the frame
    adView.frame = CGRectMake(adView.frame.origin.x, adView.frame.origin.y, self.adSize.size.width, self.adSize.size.height);
    
    [self writeJavascript:@"cordova.fireDocumentEvent('onReceiveAd');"];
}

- (void)adView:(GADBannerView *)view didFailToReceiveAdWithError:(GADRequestError *)error {
    NSLog(@"%s: Failed to receive ad with error: %@", __PRETTY_FUNCTION__, [error localizedFailureReason]);

    // Since we're passing error data back through Cordova, we need to set this up.
    NSString *jsString = @"cordova.fireDocumentEvent('onFailedToReceiveAd',{ 'error': '%@' });";
    [self writeJavascript:[NSString stringWithFormat:jsString, [error localizedFailureReason]]];
}

- (void)adViewWillPresentScreen:(GADBannerView *)adView {
    [self writeJavascript: @"cordova.fireDocumentEvent('onPresentScreen');"];
}

- (void)adViewDidDismissScreen:(GADBannerView *)adView {
    [self writeJavascript: @"cordova.fireDocumentEvent('onDismissScreen');"];
}

- (void)adViewWillLeaveApplication:(GADBannerView *)adView {
    [self writeJavascript: @"cordova.fireDocumentEvent('onLeaveApplication');"];
}

#pragma mark GADInterstitialDelegate implementation

- (void)interstitialDidReceiveAd:(GADInterstitial *)interstitial {
    NSLog(@"%s: Received ad successfully.", __PRETTY_FUNCTION__);

    [interstitial presentFromRootViewController:self.viewController];
    [self writeJavascript:@"cordova.fireDocumentEvent('onReceiveAd');"];
}

- (void)interstitial:(GADBannerView *)interstitial didFailToReceiveAdWithError:(GADRequestError *)error {
    NSLog(@"%s: Failed to receive ad with error: %@", __PRETTY_FUNCTION__, [error localizedFailureReason]);

    // Since we're passing error data back through Cordova, we need to set this up.
    NSString *jsString = @"cordova.fireDocumentEvent('onFailedToReceiveAd',{ 'error': '%@' });";
    [self writeJavascript:[NSString stringWithFormat:jsString, [error localizedFailureReason]]];
}

- (void)interstitialWillPresentScreen:(GADInterstitial *)interstitial {
    [self writeJavascript: @"cordova.fireDocumentEvent('onPresentScreen');"];
}

- (void)interstitialWillDismissScreen:(GADInterstitial *)interstitial {
    [self writeJavascript: @"cordova.fireDocumentEvent('onDismissScreen');"];
}

- (void)interstitialWillLeaveApplication:(GADInterstitial *)interstitial {
    [self writeJavascript: @"cordova.fireDocumentEvent('onLeaveApplication');"];
}

#pragma mark Cleanup

- (void)dealloc {
    
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIDeviceOrientationDidChangeNotification
                                                  object:nil];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"AGWebViewScrollViewContentInsetChanged"
                                                  object:self.webView];
     
    
    bannerView_.delegate = nil;
    interstitial_.delegate = nil;
}

@end
