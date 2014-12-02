#import "SocialSharing.h"
#import <Cordova/CDV.h>
#import <Social/Social.h>
#import <Foundation/NSException.h>
#import <MobileCoreServices/MobileCoreServices.h>

@implementation SocialSharing {
  UIPopoverController *_popover;
}

- (void)pluginInitialize {
}

- (void)available:(CDVInvokedUrlCommand*)command {
  BOOL avail = NO;
  if (NSClassFromString(@"UIActivityViewController")) {
    avail = YES;
  }
  CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:avail];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (NSString*)getIPadPopupCoordinates {
  return [self.webView stringByEvaluatingJavaScriptFromString:@"window.plugins.socialsharing.iPadPopupCoordinates();"];
}

- (CGRect)getPopupRectFromIPadPopupCoordinates:(NSArray*)comps {
  CGRect rect = CGRectZero;
  if ([comps count] == 4) {
    rect = CGRectMake([[comps objectAtIndex:0] integerValue], [[comps objectAtIndex:1] integerValue], [[comps objectAtIndex:2] integerValue], [[comps objectAtIndex:3] integerValue]);
  }
  return rect;
}

- (void)share:(CDVInvokedUrlCommand*)command {
  
  if (!NSClassFromString(@"UIActivityViewController")) {
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"not available"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    return;
  }
  
  NSString *message   = [command.arguments objectAtIndex:0];
  NSString *subject   = [command.arguments objectAtIndex:1];
  NSArray  *filenames = [command.arguments objectAtIndex:2];
  NSString *urlString = [command.arguments objectAtIndex:3];
  
  NSMutableArray *activityItems = [[NSMutableArray alloc] init];
  [activityItems addObject:message];
  
  NSMutableArray *files = [[NSMutableArray alloc] init];
  if (filenames != (id)[NSNull null] && filenames.count > 0) {
    for (NSString* filename in filenames) {
      NSObject *file = [self getImage:filename];
      if (file == nil) {
        file = [self getFile:filename];
      }
      if (file != nil) {
        [files addObject:file];
      }
    }
    [activityItems addObjectsFromArray:files];
  }
  
  if (urlString != (id)[NSNull null]) {
    [activityItems addObject:[NSURL URLWithString:urlString]];
  }
  
  UIActivity *activity = [[UIActivity alloc] init];
  NSArray *applicationActivities = [[NSArray alloc] initWithObjects:activity, nil];
  UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:applicationActivities];
  if (subject != (id)[NSNull null]) {
    [activityVC setValue:subject forKey:@"subject"];
  }
  
  [activityVC setCompletionHandler:^(NSString *activityType, BOOL completed) {
    [self cleanupStoredFiles];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:completed];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }];
  
  // possible future addition: exclude some share targets.. if building locally you may uncomment these lines
  //    NSArray * excludeActivities = @[UIActivityTypeAssignToContact, UIActivityTypeCopyToPasteboard];
  //    activityVC.excludedActivityTypes = excludeActivities;
  
  // iPad on iOS >= 8 needs a different approach
  if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
    NSString* iPadCoords = [self getIPadPopupCoordinates];
    if (![iPadCoords isEqual:@"-1,-1,-1,-1"]) {
      NSArray *comps = [iPadCoords componentsSeparatedByString:@","];
      CGRect rect = [self getPopupRectFromIPadPopupCoordinates:comps];
      if ([activityVC respondsToSelector:@selector(popoverPresentationController)]) {
        #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000 // iOS 8.0 supported
          activityVC.popoverPresentationController.sourceView = self.webView;
          activityVC.popoverPresentationController.sourceRect = rect;
        #endif
      } else {
        _popover = [[UIPopoverController alloc] initWithContentViewController:activityVC];
        _popover.delegate = self;
        [_popover presentPopoverFromRect:rect inView:self.webView permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
      }
    } else if ([activityVC respondsToSelector:@selector(popoverPresentationController)]) {
      #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000 // iOS 8.0 supported
        activityVC.popoverPresentationController.sourceView = self.webView;
        // position the popup at the bottom, just like iOS < 8 did (and iPhone still does on iOS 8)
        NSArray *comps = [NSArray arrayWithObjects:
            [NSNumber numberWithInt:(self.viewController.view.frame.size.width/2)-200],
            [NSNumber numberWithInt:self.viewController.view.frame.size.height],
            [NSNumber numberWithInt:400],
            [NSNumber numberWithInt:400],
            nil];
        CGRect rect = [self getPopupRectFromIPadPopupCoordinates:comps];
        activityVC.popoverPresentationController.sourceRect = rect;
      #endif
    }
  }
  [self.viewController presentViewController:activityVC animated:YES completion:nil];
}

- (void)shareViaTwitter:(CDVInvokedUrlCommand*)command {
  [self shareViaInternal:command type:SLServiceTypeTwitter];
}

- (void)shareViaFacebook:(CDVInvokedUrlCommand*)command {
  [self shareViaInternal:command type:SLServiceTypeFacebook];
}

- (void)shareViaFacebookWithPasteMessageHint:(CDVInvokedUrlCommand*)command {
  [self shareViaInternal:command type:SLServiceTypeFacebook];
}

- (void)shareVia:(CDVInvokedUrlCommand*)command {
  [self shareViaInternal:command type:[command.arguments objectAtIndex:4]];
}

- (bool)isAvailableForSharing:(CDVInvokedUrlCommand*)command
                         type:(NSString *) type {
  // wrapped in try-catch, because isAvailableForServiceType may crash if an invalid type is passed
  @try {
    return [SLComposeViewController isAvailableForServiceType:type];
  }
  @catch (NSException* exception) {
    return false;
  }
}

- (void)shareViaInternal:(CDVInvokedUrlCommand*)command
                    type:(NSString *) type {
  
  NSString *message   = [command.arguments objectAtIndex:0];
  // subject is not supported by the SLComposeViewController
  NSArray  *filenames = [command.arguments objectAtIndex:2];
  NSString *urlString = [command.arguments objectAtIndex:3];
  
  // boldly invoke the target app, because the phone will display a nice message asking to configure the app
  SLComposeViewController *composeViewController = [SLComposeViewController composeViewControllerForServiceType:type];
  if (message != (id)[NSNull null]) {
    [composeViewController setInitialText:message];
  }
  
  for (NSString* filename in filenames) {
    UIImage* image = [self getImage:filename];
    if (image != nil) {
      [composeViewController addImage:image];
    }
  }
  
  if (urlString != (id)[NSNull null]) {
    [composeViewController addURL:[NSURL URLWithString:urlString]];
  }
  [self.viewController presentViewController:composeViewController animated:YES completion:nil];
  
  [composeViewController setCompletionHandler:^(SLComposeViewControllerResult result) {
    // now check for availability of the app and invoke the correct callback
    if ([self isAvailableForSharing:command type:type]) {
      CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:SLComposeViewControllerResultDone == result];
      [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    } else {
      CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"not available"];
      [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
    // required for iOS6 (issues #162 and #167)
    [self.viewController dismissViewControllerAnimated:YES completion:nil];
  }];
}

- (NSString*) getBasenameFromAttachmentPath:(NSString*)path {
  if ([path hasPrefix:@"base64:"]) {
    NSString* pathWithoutPrefix = [path stringByReplacingOccurrencesOfString:@"base64:" withString:@""];
    return [pathWithoutPrefix substringToIndex:[pathWithoutPrefix rangeOfString:@"//"].location];
  }
  return path;
}

- (NSString*) getMimeTypeFromFileExtension:(NSString*)extension {
  if (!extension) {
    return nil;
  }
  // Get the UTI from the file's extension
  CFStringRef ext = (CFStringRef)CFBridgingRetain(extension);
  CFStringRef type = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext, NULL);
  // Converting UTI to a mime type
  NSString *result = (NSString*)CFBridgingRelease(UTTypeCopyPreferredTagWithClass(type, kUTTagClassMIMEType));
  CFRelease(ext);
  CFRelease(type);
  return result;
}

- (bool)canShareViaWhatsApp {
  return [[UIApplication sharedApplication] canOpenURL: [NSURL URLWithString:@"whatsapp://app"]];
}

// this is only an internal test method for now, can be used to open a share sheet with 'Open in xx' links for tumblr, drive, dropbox, ..
- (void)openImage:(NSString *)imageName {
  UIImage* image =[self getImage:imageName];
  if (image != nil) {
    NSString * savePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/myTempImage.jpg"];
    [UIImageJPEGRepresentation(image, 1.0) writeToFile:savePath atomically:YES];
    _documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:savePath]];
    _documentInteractionController.UTI = @""; // TODO find the scheme for google drive and create a shareViaGoogleDrive function
    [_documentInteractionController presentOpenInMenuFromRect:CGRectMake(0, 0, 0, 0) inView:self.viewController.view animated: YES];
  }
}

- (void)shareViaWhatsApp:(CDVInvokedUrlCommand*)command {
  
  if ([self canShareViaWhatsApp]) {
    NSString *message   = [command.arguments objectAtIndex:0];
    // subject is not supported by the SLComposeViewController
    NSArray  *filenames = [command.arguments objectAtIndex:2];
    NSString *urlString = [command.arguments objectAtIndex:3];
    
    // only use the first image (for now.. maybe we can share in a loop?)
    UIImage* image = nil;
    for (NSString* filename in filenames) {
      image = [self getImage:filename];
      break;
    }
    
    // with WhatsApp, we can share an image OR text+url.. image wins if set
    if (image != nil) {
      NSString * savePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/whatsAppTmp.wai"];
      [UIImageJPEGRepresentation(image, 1.0) writeToFile:savePath atomically:YES];
      _documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:savePath]];
      _documentInteractionController.UTI = @"net.whatsapp.image";
      [_documentInteractionController presentOpenInMenuFromRect:CGRectMake(0, 0, 0, 0) inView:self.viewController.view animated: YES];
    } else {
      // append an url to a message, if both are passed
      NSString * shareString = @"";
      if (message != (id)[NSNull null]) {
        shareString = message;
      }
      if (urlString != (id)[NSNull null]) {
        if ([shareString isEqual: @""]) {
          shareString = urlString;
        } else {
          shareString = [NSString stringWithFormat:@"%@ %@", shareString, urlString];
        }
      }
      NSString * encodedShareString = [shareString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
      // also encode the '=' character
      encodedShareString = [encodedShareString stringByReplacingOccurrencesOfString:@"=" withString:@"%3D"];
      NSString * encodedShareStringForWhatsApp = [NSString stringWithFormat:@"whatsapp://send?text=%@", encodedShareString];
      
      NSURL *whatsappURL = [NSURL URLWithString:encodedShareStringForWhatsApp];
      [[UIApplication sharedApplication] openURL: whatsappURL];
    }
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    
  } else {
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"not available"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }
}

-(UIImage*)getImage: (NSString *)imageName {
  UIImage *image = nil;
  if (imageName != (id)[NSNull null]) {
    if ([imageName hasPrefix:@"http"]) {
      image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:imageName]]];
    } else if ([imageName hasPrefix:@"www/"]) {
      image = [UIImage imageNamed:imageName];
    } else if ([imageName hasPrefix:@"file://"]) {
      image = [UIImage imageWithData:[NSData dataWithContentsOfFile:[[NSURL URLWithString:imageName] path]]];
    } else if ([imageName hasPrefix:@"data:"]) {
      // using a base64 encoded string
      NSURL *imageURL = [NSURL URLWithString:imageName];
      NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
      image = [UIImage imageWithData:imageData];
    } else if ([imageName hasPrefix:@"assets-library://"]) {
      // use assets-library
      NSURL *imageURL = [NSURL URLWithString:imageName];
      NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
      image = [UIImage imageWithData:imageData];
    } else {
      // assume anywhere else, on the local filesystem
      image = [UIImage imageWithData:[NSData dataWithContentsOfFile:imageName]];
    }
  }
  return image;
}

-(NSURL*)getFile: (NSString *)fileName {
  NSURL *file = nil;
  if (fileName != (id)[NSNull null]) {
    if ([fileName hasPrefix:@"http"]) {
      NSURL *url = [NSURL URLWithString:fileName];
      NSData *fileData = [NSData dataWithContentsOfURL:url];
      file = [NSURL fileURLWithPath:[self storeInFile:(NSString*)[[fileName componentsSeparatedByString: @"/"] lastObject] fileData:fileData]];
    } else if ([fileName hasPrefix:@"www/"]) {
      NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
      NSString *fullPath = [NSString stringWithFormat:@"%@/%@", bundlePath, fileName];
      file = [NSURL fileURLWithPath:fullPath];
    } else if ([fileName hasPrefix:@"file://"]) {
      // stripping the first 6 chars, because the path should start with / instead of file://
      file = [NSURL fileURLWithPath:[fileName substringFromIndex:6]];
    } else if ([fileName hasPrefix:@"data:"]) {
      // using a base64 encoded string
      // extract some info from the 'fileName', which is for example: data:text/calendar;base64,<encoded stuff here>
      NSString *fileType = (NSString*)[[[fileName substringFromIndex:5] componentsSeparatedByString: @";"] objectAtIndex:0];
      fileType = (NSString*)[[fileType componentsSeparatedByString: @"/"] lastObject];
      NSString *base64content = (NSString*)[[fileName componentsSeparatedByString: @","] lastObject];
      NSData *fileData = [NSData dataFromBase64String:base64content];
      file = [NSURL fileURLWithPath:[self storeInFile:[NSString stringWithFormat:@"%@.%@", @"file", fileType] fileData:fileData]];
    } else {
      // assume anywhere else, on the local filesystem
      file = [NSURL fileURLWithPath:fileName];
    }
  }
  return file;
}

-(NSString*) storeInFile: (NSString*) fileName
                fileData: (NSData*) fileData {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *documentsDirectory = [paths objectAtIndex:0];
  NSString *filePath = [documentsDirectory stringByAppendingPathComponent:fileName];
  [fileData writeToFile:filePath atomically:YES];
  _tempStoredFile = filePath;
  return filePath;
}

- (void) cleanupStoredFiles {
  if (_tempStoredFile != nil) {
    NSError *error;
    [[NSFileManager defaultManager]removeItemAtPath:_tempStoredFile error:&error];
  }
}

#pragma mark - UIPopoverControllerDelegate methods

- (void)popoverController:(UIPopoverController *)popoverController willRepositionPopoverToRect:(inout CGRect *)rect inView:(inout UIView **)view {
  NSArray *comps = [[self getIPadPopupCoordinates] componentsSeparatedByString:@","];
  CGRect newRect = [self getPopupRectFromIPadPopupCoordinates:comps];
  rect->origin = newRect.origin;
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController {
  _popover = nil;
}

@end