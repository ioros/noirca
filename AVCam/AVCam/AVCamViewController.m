/*
 File: AVCamViewController.m
 Abstract: View controller for camera interface.
 Version: 3.1
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 */

#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

#import "AVCamViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/CGImageSource.h>
#import <ImageIO/CGImageProperties.h>


#import <MediaPlayer/MediaPlayer.h>

#import "AVCamPreviewView.h"

static void * CapturingStillImageContext = &CapturingStillImageContext;
static void * RecordingContext = &RecordingContext;
static void * SessionRunningAndDeviceAuthorizedContext = &SessionRunningAndDeviceAuthorizedContext;

@interface AVCamViewController () <AVCaptureFileOutputRecordingDelegate>

// For use in the storyboards.
@property (nonatomic, weak) IBOutlet AVCamPreviewView *previewView;

// Session management.
@property (nonatomic) dispatch_queue_t sessionQueue; // Communicate with the session and other session objects on this queue.
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDevice *videoDevice;
@property (nonatomic) AVCaptureStillImageOutput *stillImageOutput;

// Utilities.
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;
@property (nonatomic) BOOL lockInterfaceRotation;
@property (nonatomic) id runtimeErrorHandlingObserver;

@end

@implementation AVCamViewController

- (BOOL)isSessionRunningAndDeviceAuthorized
{
	return [[self session] isRunning] && [self isDeviceAuthorized];
}

+ (NSSet *)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized
{
	return [NSSet setWithObjects:@"session.running", @"deviceAuthorized", nil];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	[self start];
}

#pragma mark Start

-(void)start
{
	modeCurrent = 2;
	isPressed = 0;
	modeLens = @"auto";
	
	[self templateStart];
	[self captureStart];
	[self savingEnabledCheck];
}

-(void)savingEnabledCheck
{
	ALAuthorizationStatus status = [ALAssetsLibrary authorizationStatus];
	if (status != ALAuthorizationStatusAuthorized && status!= ALAuthorizationStatusNotDetermined) {
		_loadingIndicator.backgroundColor = [UIColor redColor];
		isAuthorized = 0;
	}
	else{
		isAuthorized = 1;
	}
	
	if( isAuthorized == 0 ){
		[self displayModeMessage:@"Settings -> Privacy -> Photos"];
	}
}

-(void)templateStart
{
	screen = [[UIScreen mainScreen] bounds];
	tileSize = screen.size.width/8;
	
	_gridView.frame = CGRectMake(0, 0, screen.size.width, screen.size.height);
	_gridView.backgroundColor = [UIColor clearColor];
	
	_blackScreenView.frame = CGRectMake(0, 0, screen.size.width, screen.size.height);
	_blackScreenView.backgroundColor = [UIColor blackColor];
	_blackScreenView.alpha = 0;
	
	_centerHorizontalGrid.backgroundColor = [UIColor colorWithWhite:1 alpha:1];
	_centerHorizontalGrid.frame = CGRectMake(screen.size.width/2, screen.size.height/2, 1, 1);
	
	_centerVerticalGrid.backgroundColor = [UIColor colorWithWhite:1 alpha:1];
	_centerVerticalGrid.frame = CGRectMake(screen.size.width/2, screen.size.height/2, 1, 1);
	
	_centerHorizontalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerHorizontalGridSecondary1.frame = CGRectMake(0, 0, screen.size.width, 1);
	
	_centerHorizontalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerHorizontalGridSecondary2.frame = CGRectMake( 0, screen.size.height, screen.size.width, 1);
	
	_centerVerticalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerVerticalGridSecondary1.frame = CGRectMake(0, 0, 1, screen.size.height);
	
	_centerVerticalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerVerticalGridSecondary2.frame = CGRectMake(screen.size.width, 0, 1, screen.size.height);
	
	_modeLabel.frame = CGRectMake(screen.size.width-(tileSize*5), screen.size.height - tileSize, tileSize*4, tileSize);
	_modeButton.frame = CGRectMake(0, screen.size.height-tileSize, screen.size.width, tileSize);
	
	_loadingIndicator.backgroundColor = [UIColor whiteColor];
	_loadingIndicator.frame = CGRectMake( (screen.size.width - ((tileSize/2)+2)), (screen.size.height - ((tileSize/2)+2)), 4, 4);
	_loadingIndicator.layer.cornerRadius = 2.5;
	
	_touchIndicatorX.backgroundColor = [UIColor whiteColor];
	_touchIndicatorX.frame = CGRectMake( (screen.size.width - tileSize)+ 15, (screen.size.height - tileSize)+ 15, 5, 5);
	_touchIndicatorX.layer.cornerRadius = 2.5;
	
	_focusLabel.frame = CGRectMake(tileSize/4, screen.size.height-tileSize, tileSize, tileSize);
	_isoLabel.frame = CGRectMake(tileSize/4 + tileSize, screen.size.height-tileSize, tileSize, tileSize);
	
	_focusTextLabel.frame = CGRectMake(tileSize/4, screen.size.height-tileSize-13, tileSize, tileSize);
	_isoTextLabel.frame = CGRectMake(tileSize/4 + tileSize, screen.size.height-tileSize-13, tileSize, tileSize);
	
	_touchIndicatorX.frame = CGRectMake( screen.size.width/2, screen.size.height/2, 1,1 );
	_touchIndicatorY.frame = CGRectMake( screen.size.width/2, screen.size.height/2, 1, 1);
	
	_isoTextLabel.alpha = 0;
	_focusTextLabel.alpha = 0;
	
	[self gridAnimationIn];
}

-(void)gridAnimationIn
{
	NSLog(@"grid animatio -> In");
	
	[UIView beginAnimations: @"Splash Intro" context:nil];
	[UIView setAnimationDuration:0.3];
	[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
	
	_centerHorizontalGrid.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"tile.png"]];
	_centerHorizontalGrid.frame = CGRectMake(0, screen.size.height/2, screen.size.width, 1);
	
	_centerVerticalGrid.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
	_centerVerticalGrid.frame = CGRectMake(screen.size.width/2, 0, 1, screen.size.height);
	
	_centerHorizontalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
	_centerHorizontalGridSecondary1.frame = CGRectMake(0, screen.size.height/3, screen.size.width, 1);
	
	_centerHorizontalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
	_centerHorizontalGridSecondary2.frame = CGRectMake( 0, (screen.size.height/3)*2, screen.size.width, 1);
	
	_centerVerticalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
	_centerVerticalGridSecondary1.frame = CGRectMake(screen.size.width/3, 0, 1, screen.size.height);
	
	_centerVerticalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
	_centerVerticalGridSecondary2.frame = CGRectMake((screen.size.width/3)*2, 0, 1, screen.size.height);
	
	[UIView commitAnimations];
}

-(void)gridAnimationOut
{
	NSLog(@"grid animatio -> Out");
	[UIView beginAnimations: @"Splash Intro" context:nil];
	[UIView setAnimationDuration:0.5];
	[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
	
	_centerHorizontalGrid.frame = CGRectMake(screen.size.width/4, screen.size.height/2, screen.size.width/2, 1);
	
	_centerVerticalGrid.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
	_centerVerticalGrid.frame = CGRectMake(screen.size.width/2, (screen.size.height/2)-((screen.size.height/40)/2), 1, screen.size.height/40);
	
	_centerHorizontalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerHorizontalGridSecondary1.frame = CGRectMake(0, 0, screen.size.width, 1);
	
	_centerHorizontalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerHorizontalGridSecondary2.frame = CGRectMake( 0, screen.size.height, screen.size.width, 1);
	
	_centerVerticalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerVerticalGridSecondary1.frame = CGRectMake(0, 0, 1, screen.size.height);
	
	_centerVerticalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerVerticalGridSecondary2.frame = CGRectMake(screen.size.width, 0, 1, screen.size.height);
	
	[UIView commitAnimations];
}

-(void)updateLensData
{
	if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8.0")) {
		_focusLabel.text = [NSString stringWithFormat:@"%d%%", (int)([_videoDevice lensPosition] * 100) ];
		_isoLabel.text = [NSString stringWithFormat:@"%d", (int)([_videoDevice ISO])+2 ];
		_isoTextLabel.alpha = 1;
		_focusTextLabel.alpha = 1;
	}
}

-(void)modeSetAuto
{
	modeLens = @"auto";
	[self displayModeMessage:@"Automatic Mode"];
	
	[UIView beginAnimations: @"Splash Intro" context:nil];
	[UIView setAnimationDuration:0.1];
	[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
	_touchIndicatorX.frame = CGRectMake( screen.size.width/2, screen.size.height/2, 1,1 );
	_touchIndicatorY.frame = CGRectMake( screen.size.width/2, screen.size.height/2, 1, 1);
	_touchIndicatorX.alpha = 1;
	_touchIndicatorY.alpha = 1;
	[UIView commitAnimations];
	
	[_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
	[_videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
}


-(void)captureStart
{
	// Create the AVCaptureSession
	AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetPhoto; //gets best image quality
	[self setSession:session];
	
	// Setup the preview view
	[[self previewView] setSession:session];
	
	// Check for device authorization
	[self checkDeviceAuthorizationStatus];
	
	// In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
	// Why not do all of this on the main queue?
	// -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue so that the main queue isn't blocked (which keeps the UI responsive).
	
	dispatch_queue_t sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
	[self setSessionQueue:sessionQueue];
	
	dispatch_async(sessionQueue, ^{
		[self setBackgroundRecordingID:UIBackgroundTaskInvalid];
		
		NSError *error = nil;
		
		_videoDevice = [AVCamViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
		AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice error:&error];
		
		if (error)
		{
			NSLog(@"%@", error);
		}
		
		if ([session canAddInput:videoDeviceInput])
		{
			[session addInput:videoDeviceInput];
			//			[self setVideoDeviceInput:videoDeviceInput];
			
			dispatch_async(dispatch_get_main_queue(), ^{
				// Why are we dispatching this to the main queue?
				// Because AVCaptureVideoPreviewLayer is the backing layer for AVCamPreviewView and UIView can only be manipulated on main thread.
				// Note: As an exception to the above rule, it is not necessary to serialize video orientation changes on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
				
				[[(AVCaptureVideoPreviewLayer *)[[self previewView] layer] connection] setVideoOrientation:(AVCaptureVideoOrientation)[self interfaceOrientation]];
			});
		}
		
		AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
		if ([session canAddOutput:stillImageOutput])
		{
			[stillImageOutput setOutputSettings:@{AVVideoCodecKey : AVVideoCodecJPEG}];
			[session addOutput:stillImageOutput];
			[self setStillImageOutput:stillImageOutput];
		}
	});
    [self installVolume];
	
	[self apiContact:@"noirca":@"analytics":@"launch":@"1"];
    
    queue = dispatch_queue_create("com.XXIIVV.SaveImageQueue", NULL);
}

- (void)viewWillAppear:(BOOL)animated
{
	dispatch_async([self sessionQueue], ^{
		[self addObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:SessionRunningAndDeviceAuthorizedContext];
		[self addObserver:self forKeyPath:@"stillImageOutput.capturingStillImage" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:CapturingStillImageContext];
		//		[self addObserver:self forKeyPath:@"movieFileOutput.recording" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:RecordingContext];
		//		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];
		
		__weak AVCamViewController *weakSelf = self;
		[self setRuntimeErrorHandlingObserver:[[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:[self session] queue:nil usingBlock:^(NSNotification *note) {
			AVCamViewController *strongSelf = weakSelf;
			dispatch_async([strongSelf sessionQueue], ^{
				// Manually restarting the session since it must have been stopped due to an error.
				[[strongSelf session] startRunning];
			});
		}]];
		[[self session] startRunning];
	});
}

- (void)viewDidDisappear:(BOOL)animated
{
	dispatch_async([self sessionQueue], ^{
		[[self session] stopRunning];
		
		//		[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];
		[[NSNotificationCenter defaultCenter] removeObserver:[self runtimeErrorHandlingObserver]];
		
		[self removeObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" context:SessionRunningAndDeviceAuthorizedContext];
		[self removeObserver:self forKeyPath:@"stillImageOutput.capturingStillImage" context:CapturingStillImageContext];
		[self removeObserver:self forKeyPath:@"movieFileOutput.recording" context:RecordingContext];
	});
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

- (BOOL)shouldAutorotate
{
	// Disable autorotation of the interface when recording is in progress.
	return ![self lockInterfaceRotation];
}

- (NSUInteger)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskAll;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	[[(AVCaptureVideoPreviewLayer *)[[self previewView] layer] connection] setVideoOrientation:AVCaptureVideoOrientationPortrait];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == CapturingStillImageContext)
	{
		BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
		
		if (isCapturingStillImage)
		{
			[self runStillImageCaptureAnimation];
		}
	}
	else if (context == RecordingContext)
	{
		BOOL isRecording = [change[NSKeyValueChangeNewKey] boolValue];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (isRecording)
			{
			}
			else
			{
			}
		});
	}
	else if (context == SessionRunningAndDeviceAuthorizedContext)
	{
		BOOL isRunning = [change[NSKeyValueChangeNewKey] boolValue];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (isRunning)
			{
			}
			else
			{
			}
		});
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

#pragma mark Touch

- (void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	UITouch *theTouch = [touches anyObject];
	startPoint = [theTouch locationInView:self.focusView];
	
	isReady = 1;
	
	[self updateLensData];
}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	UITouch *theTouch = [touches anyObject];
	movedPoint = [theTouch locationInView:self.focusView];
	
	[self updateLensData];
}

- (void) touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	if(isReady == 1){
		[self takePicture];
		[self updateLensData];
	}
	
	isPressed = 0;
}

#pragma mark Picture

-(void)takePicture
{
	if( isAuthorized == 0 ){
		[self savingEnabledCheck];
		[self displayModeMessage:@"Authorize Noirca: Settings -> Privacy -> Photos"];
		return;
	}
	if( isRendering > 2 ){  //disallow if the user has already taken 3 images
		[self displayModeMessage:@"wait"];
		return;
	}

	int pictureCount = [[[NSUserDefaults standardUserDefaults] objectForKey:@"photoCount"] intValue];
	
	// Remove preview image
	if( self.previewThing.image != NULL ){
		[UIView beginAnimations: @"Splash Intro" context:nil];
		[UIView setAnimationDuration:1];
		[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
		_loadingIndicator.alpha = 1;
		_blackScreenView.alpha = 0;
		[UIView commitAnimations];
		
		self.previewThing.image = NULL;
	
		[self gridAnimationIn];
		[self displayModeMessage:@"Ready"];
		return;
	}
	
	_previewThing.alpha = 0;
	
	// Save
	isRendering++;
	
	[[[self stillImageOutput] connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:AVCaptureVideoOrientationPortrait];
	
	[[self stillImageOutput] captureStillImageAsynchronouslyFromConnection:[[self stillImageOutput] connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
		
		if (imageDataSampleBuffer)
		{
			NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
			
            CFDictionaryRef metaDict = CMCopyDictionaryOfAttachments(NULL, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
            
            EXIF = (__bridge NSDictionary*)metaDict;
            @autoreleasepool
            {
                currentImageData = imageData;
                previewImage = [self filterMode:[self imageScaledToScreen:[[UIImage alloc] initWithData:imageData]]];
            }
            [self checkLoop];
		}
	}];
	
	[self gridAnimationOut];
	[self displayModeMessage:[NSString stringWithFormat:@"%d",pictureCount]];
	_blackScreenView.alpha = 1;
	
	// save
	[[NSUserDefaults standardUserDefaults] setInteger:pictureCount+1 forKey:@"photoCount"];
}

- (UIImage *)cropImagetoScreen:(UIImage *)image
{
    //CGRect CropRect = CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height+15);
    CGSize screenSize =[[UIScreen mainScreen] bounds].size;
    
    float ratio = screenSize.width/screenSize.height;
    
    CGRect rect = CGRectMake(0, 0, CGImageGetWidth([image CGImage]), CGImageGetHeight([image CGImage]));
    
    float currentRatio = rect.size.height/rect.size.width;
    
    if(currentRatio>ratio) {
        float newheight = rect.size.width*ratio;
        rect.origin.y = (rect.size.height-newheight)/2;
        rect.size.height = newheight;
    }
    
    CGImageRef imageRef = CGImageCreateWithImageInRect([image CGImage], rect);
    UIImage *cropped = [UIImage imageWithCGImage:imageRef scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(imageRef);
    
    return cropped;
}

-(UIImage*)imageScaledToScreen: (UIImage*) sourceImage
{
    //CGSize bounds = sourceImage.size;
    float oldHeight = sourceImage.size.height;
    float screenHeight =[[UIScreen mainScreen] bounds].size.height*[[UIScreen mainScreen] scale];
    float scaleFactor = screenHeight / oldHeight;
    
    float newWidth = sourceImage.size.width * scaleFactor;
    float newHeight = screenHeight;
    
    UIGraphicsBeginImageContext(CGSizeMake(newWidth, newHeight));
    [sourceImage drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
    /*return [UIImage imageWithCGImage:[newImage CGImage]
                               scale:1.0
                         orientation: UIImageOrientationRight];*/
}

-(void)displayModeMessage :(NSString*)message
{
	_modeLabel.alpha = 1;
	_modeLabel.text = message;
	
	[UIView beginAnimations: @"Splash Intro" context:nil];
	[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
	[UIView setAnimationDelay:2];
	[UIView setAnimationDuration:0.5];
	_modeLabel.alpha = 0;
	_loadingIndicator.alpha = 1;
	[UIView commitAnimations];
}

-(void)checkLoop
{
	// Ready
	if( currentImageData != NULL){
		
		[UIView beginAnimations: @"Splash Intro" context:nil];
		[UIView setAnimationDuration:0.5];
		[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
		_previewThing.alpha = 1;
		[UIView commitAnimations];
		
		self.previewThing.image = previewImage;

        [self saveImage:currentImageData withMode:modeCurrent andEXIF:EXIF];
        currentImageData=NULL;
		imageInMemory = NULL;
	}
	NSLog(@"check");
}

-(void)saveImage:(NSData*)imageData withMode:(int)mode andEXIF:(NSDictionary*)exifData
{
	UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;
    bgTask =   [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        // Clean up any unfinished task business by marking where you
        // stopped or ending the task outright.
        [[UIApplication sharedApplication] endBackgroundTask:bgTask];
    }];
    
    
    dispatch_async(queue, ^{
        @autoreleasepool
        {
            UIImage *imageToSave = [self cropImagetoScreen:[[UIImage alloc] initWithData:imageData]];
            
            imageToSave = [self filterMode:imageToSave];

            //imageToSave = [self cropImagetoScreen:imageToSave];
            NSData *imgData = UIImageJPEGRepresentation(imageToSave,1);
            NSLog(@"Size of Image(bytes): %lu",(unsigned long)[imgData length]);
            imageToSave = NULL;
            
            NSMutableDictionary *exifm = [exifData mutableCopy];
            
            //[exifm setObject:[NSNumber numberWithInt:6] forKey:@"Orientation"];
            [[[ALAssetsLibrary alloc] init] writeImageDataToSavedPhotosAlbum:imgData metadata:exifm completionBlock:^(NSURL *assetURL, NSError *error){
                [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                
            }];
            isRendering--;
        }
        
        
    });
    
	/*[[[ALAssetsLibrary alloc] init] writeImageToSavedPhotosAlbum:[imageInMemory CGImage] orientation:(ALAssetOrientation)[imageInMemory imageOrientation] completionBlock:nil];*/
}

#pragma mark Filters

-(UIImage *) filterMode:(UIImage *)image
{
	const int RED = 1, GREEN = 2, BLUE = 3;
	
	CGRect imageRect = CGRectMake(0, 0, image.size.width, image.size.height);
	
	int width = imageRect.size.width, height = imageRect.size.height;
	
	uint32_t * pixels = (uint32_t *) malloc(width*height*sizeof(uint32_t));
	memset(pixels, 0, width * height * sizeof(uint32_t));
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * sizeof(uint32_t), colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedLast);
	
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), [image CGImage]);
	
	for(int y = 0; y < height; y++) {
		for(int x = 0; x < width; x++) {
			uint8_t * rgbaPixel = (uint8_t *) &pixels[y*width+x];
			uint32_t gray = (0.0*rgbaPixel[RED]+0.0*rgbaPixel[GREEN]+0.9*rgbaPixel[BLUE]);
			
			float grayFloat = gray;
			
			float whiteContent = (float)grayFloat/255;
			
			grayFloat = (grayFloat * whiteContent * 1.25)+60;
			
			whiteContent = (float)grayFloat/255;
			grayFloat = grayFloat + (whiteContent * 200.5)-80;
			
			// Cap
			if(grayFloat > 255){ grayFloat = 255; }
			if(grayFloat < 0){ grayFloat = 00; }
			
			gray = (int)grayFloat;
			
			rgbaPixel[RED] = gray;
			rgbaPixel[GREEN] = gray;
			rgbaPixel[BLUE] = gray;
		}
	}
	
	CGImageRef newImage = CGBitmapContextCreateImage(context);
	
	CGContextRelease(context);
	CGColorSpaceRelease(colorSpace);
	free(pixels);
	
	UIImage * resultUIImage = [UIImage imageWithCGImage:newImage scale:1 orientation:UIImageOrientationUp];
	CGImageRelease(newImage);
	
	resultUIImage = [self sharpen:resultUIImage];
	
	return resultUIImage;
}

-(UIImage *) sharpen: (UIImage *)image {
	
	const int RED = 1, GREEN = 2, BLUE = 3;
	
	CGRect imageRect = CGRectMake(0, 0, CGImageGetWidth([image CGImage]),  CGImageGetHeight([image CGImage]));
	
	int width = imageRect.size.width, height = imageRect.size.height;
	
	uint32_t * pixels = (uint32_t *) malloc(width*height*sizeof(uint32_t));
	memset(pixels, 0, width * height * sizeof(uint32_t));
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * sizeof(uint32_t), colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedLast);
	
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), [image CGImage]);
	
	for(int y = 0; y < height; y++) {
		for(int x = 0; x < width; x++) {
			
			uint32_t pixelTop = 0;
			uint32_t pixelBottom = 0;
			uint32_t pixelRight = 0;
			uint32_t pixelLeft = 0;
			
			// Center
			uint8_t * rgbaPixel = (uint8_t *) &pixels[y*width+x];
			uint32_t center = (0.33*rgbaPixel[RED]+0.33*rgbaPixel[GREEN]+0.33*rgbaPixel[BLUE]);
			
			
			if(y == 0 || x == 0){
				rgbaPixel[RED] = center;
				rgbaPixel[GREEN] = center;
				rgbaPixel[BLUE] = center;
			}
			else{
				// Top
				rgbaPixel = (uint8_t *) & pixels[(y-1)*width+x];
				pixelTop = (0.33*rgbaPixel[RED]+0.33*rgbaPixel[GREEN]+0.33*rgbaPixel[BLUE]);
				rgbaPixel = (uint8_t *) & pixels[(y-1)*width+x];
				pixelBottom = (0.33*rgbaPixel[RED]+0.33*rgbaPixel[GREEN]+0.33*rgbaPixel[BLUE]);
				
				rgbaPixel = (uint8_t *) & pixels[(y-1)*width+x];
				pixelRight = (0.33*rgbaPixel[RED]+0.33*rgbaPixel[GREEN]+0.33*rgbaPixel[BLUE]);
				
				rgbaPixel = (uint8_t *) & pixels[(y-1)*width+x];
				pixelLeft = (0.33*rgbaPixel[RED]+0.33*rgbaPixel[GREEN]+0.33*rgbaPixel[BLUE]);
				
				uint32_t average = (pixelTop + pixelBottom + pixelRight + pixelLeft)/4;
				
				uint32_t centerValue = center;
				
				if( centerValue > average ){
					centerValue += (centerValue-average)*0.5;
				}
				
				// Cap
				if(centerValue > 255){ centerValue = 255; }
				
				rgbaPixel[RED] = centerValue;
				rgbaPixel[GREEN] = centerValue;
				rgbaPixel[BLUE] = centerValue;
			}
			
		}
	}
	
	CGImageRef newImage = CGBitmapContextCreateImage(context);
	
	CGContextRelease(context);
	CGColorSpaceRelease(colorSpace);
	free(pixels);
	
	UIImage * resultUIImage = [UIImage imageWithCGImage:newImage scale:1 orientation:UIImageOrientationUp];
	CGImageRelease(newImage);
	
	return resultUIImage;
	
}

#pragma mark File Output Delegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
	if (error)
		NSLog(@"%@", error);
	
	[self setLockInterfaceRotation:NO];
	
	// Note the backgroundRecordingID for use in the ALAssetsLibrary completion handler to end the background task associated with this recording. This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's -isRecording is back to NO — which happens sometime after this method returns.
	UIBackgroundTaskIdentifier backgroundRecordingID = [self backgroundRecordingID];
	[self setBackgroundRecordingID:UIBackgroundTaskInvalid];
	
	[[[ALAssetsLibrary alloc] init] writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
		if (error)
			NSLog(@"%@", error);
		
		[[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
		
		if (backgroundRecordingID != UIBackgroundTaskInvalid)
			[[UIApplication sharedApplication] endBackgroundTask:backgroundRecordingID];
	}];
}

#pragma mark Device Configuration

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
	AVCaptureDevice *captureDevice = [devices firstObject];
	
	for (AVCaptureDevice *device in devices)
	{
		if ([device position] == position)
		{
			captureDevice = device;
			break;
		}
	}
	
	return captureDevice;
}

#pragma mark UI

- (void)runStillImageCaptureAnimation
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[[[self previewView] layer] setOpacity:0.0];
		[UIView animateWithDuration:.25 animations:^{
			[[[self previewView] layer] setOpacity:1.0];
		}];
	});
}

- (void)checkDeviceAuthorizationStatus
{
	NSString *mediaType = AVMediaTypeVideo;
	
	[AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
		if (granted)
		{
			//Granted access to mediaType
			[self setDeviceAuthorized:YES];
		}
		else
		{
			//Not granted access to mediaType
			dispatch_async(dispatch_get_main_queue(), ^{
				[[[UIAlertView alloc] initWithTitle:@"AVCam!"
											message:@"AVCam doesn't have permission to use Camera, please change privacy settings"
										   delegate:self
								  cancelButtonTitle:@"OK"
								  otherButtonTitles:nil] show];
				[self setDeviceAuthorized:NO];
			});
		}
	}];
}

#pragma mark Volume Button

/* Instructions:
 1. Add the Media player framework to your project.
 2. Insert following code into the controller for your shutter view.
 3. Add [self installVolume] to your viewdidload function
 4. add your shutter trigger code to the volumeChanged function
 5. Call uninstallVolume whenever you want to remove the volume changed notification
 
 note: If the user holds the volume+ button down, the volumeChanged function will be called repeatedly, be sure to add a rate limiter if your application isn't setup to take multiple photos a second.
 
 */

float currentVolume; //Current Volume

-(void)installVolume { /*Installs the volume button view and sets up the notifications to trigger the volumechange and the resetVolume button*/
    MPVolumeView *volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-100, -100, 1, 1)];
    volumeView.showsRouteButton = NO;
    [self.previewView addSubview:volumeView];
    [self.previewView sendSubviewToBack:volumeView];
    
    [self resetVolumeButton];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(volumeChanged:)
     name:@"AVSystemController_SystemVolumeDidChangeNotification"
     object:nil];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(resetVolumeButton) name:UIApplicationDidBecomeActiveNotification object:nil];
}

-(void)uninstallVolume { /*removes notifications, install when you are closing the app or the camera view*/
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"AVSystemController_SystemVolumeDidChangeNotification"
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidBecomeActiveNotification
                                                  object:nil];
}

-(void)resetVolumeButton { /*gets the current volume and sets up the button, needs to be called when the app returns from background.*/
    currentVolume=-1;
    AVAudioPlayer* p = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"silence.wav"]] error:NULL];
    
    [p prepareToPlay];
    [p stop];
}

- (void)volumeChanged:(NSNotification *)notification{
    float volume = [[[notification userInfo] objectForKey:@"AVSystemController_AudioVolumeNotificationParameter"] floatValue];
    if( [[[notification userInfo]objectForKey:@"AVSystemController_AudioVolumeChangeReasonNotificationParameter"]isEqualToString:@"ExplicitVolumeChange"]) {
        if(volume>=currentVolume && volume>0) {
            /* Do shutter button stuff here!*/
            [self takePicture];
        }
    }
    currentVolume=volume;
}

- (IBAction)modeButton:(id)sender
{
	[_videoDevice lockForConfiguration:nil];
	
	if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8.0")) {
		return;
	}
	
	modeCurrent += 1;
	if(modeCurrent > 5){
		modeCurrent = 0;
	}
	
	if( modeCurrent == 0 ){
		[_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
		[_videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
		_loadingIndicator.backgroundColor = [UIColor redColor];
		[self displayModeMessage:@"ISO AUTO"];
	}
	if( modeCurrent == 1 ){
		[_videoDevice setExposureModeCustomWithDuration:[_videoDevice exposureDuration] ISO:120 completionHandler:nil];
		[_videoDevice setFocusMode:AVCaptureFocusModeLocked];
		_loadingIndicator.backgroundColor = [UIColor whiteColor];
		[self displayModeMessage:@"ISO 120"];
	}
	if( modeCurrent == 2 ){
		[_videoDevice setExposureModeCustomWithDuration:[_videoDevice exposureDuration] ISO:240 completionHandler:nil];
		[_videoDevice setFocusMode:AVCaptureFocusModeLocked];
		_loadingIndicator.backgroundColor = [UIColor whiteColor];
		[self displayModeMessage:@"ISO 240"];
	}
	if( modeCurrent == 3 ){
		[_videoDevice setExposureModeCustomWithDuration:[_videoDevice exposureDuration] ISO:320 completionHandler:nil];
		[_videoDevice setFocusMode:AVCaptureFocusModeLocked];
		_loadingIndicator.backgroundColor = [UIColor whiteColor];
		[self displayModeMessage:@"ISO 320"];
	}
	else if( modeCurrent == 4 ){
		[_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
		[_videoDevice setFocusModeLockedWithLensPosition:0 completionHandler:nil];
		_loadingIndicator.backgroundColor = [UIColor blackColor];
		[self displayModeMessage:@"LENS MACRO"];
	}
	if( modeCurrent == 5 ){
		[_videoDevice setExposureModeCustomWithDuration:[_videoDevice exposureDuration] ISO:60 completionHandler:nil];
		[_videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
		[_videoDevice setTorchMode:AVCaptureTorchModeOn];
		_loadingIndicator.backgroundColor = [UIColor redColor];
		[self displayModeMessage:@"FLASH"];
	}
	else{
		[_videoDevice setTorchMode:AVCaptureTorchModeOff];
	}
}

-(void)audioPlayer: (NSString *)filename;
{
	NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
	resourcePath = [resourcePath stringByAppendingString: [NSString stringWithFormat:@"/%@", filename] ];
	NSError* err;
	audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL: [NSURL fileURLWithPath:resourcePath] error:&err];
	
	audioPlayer.volume = 0.5;
	audioPlayer.numberOfLoops = 0;
	audioPlayer.currentTime = 0;
	
	if(err)	{ NSLog(@"%@",err); }
	else	{
		[audioPlayer prepareToPlay];
		[audioPlayer play];
	}
}
-(void)apiContact:(NSString*)source :(NSString*)method :(NSString*)term :(NSString*)value
{
	NSString *post = [NSString stringWithFormat:@"values={\"term\":\"%@\",\"value\":\"%@\"}",term,value];
	NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
	
	NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[postData length]];
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
	[request setURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://api.xxiivv.com/%@/%@",source,method]]];
	[request setHTTPMethod:@"POST"];
	[request setValue:postLength forHTTPHeaderField:@"Content-Length"];
	[request setValue:@"application/x-www-form-urlencoded;charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
	[request setHTTPBody:postData];
	
	NSURLResponse *response;
	NSData *POSTReply = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
	NSString *theReply = [[NSString alloc] initWithBytes:[POSTReply bytes] length:[POSTReply length] encoding: NSASCIIStringEncoding];
	NSLog(@"& API  | %@: %@",method, theReply);
	
	return;
}



@end
