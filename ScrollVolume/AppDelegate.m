//
//  AppDelegate.m
//  ScrollVolume
//
//  Created by Carlos Cesar Neves Enumo on 10/05/13.
//  Copyright (c) 2013 Carlos Cesar Neves Enumo. All rights reserved.
//

#import "AppDelegate.h"
#import <AudioToolbox/AudioServices.h>

@interface AppDelegate()
{
    id eventMonitor;
    AudioDeviceID defaultOutputDeviceID;
    NSViewAnimation *anim;
    SystemSoundID sound;
}
@property (nonatomic,weak) IBOutlet NSPanel *window;
@property (nonatomic,weak) IBOutlet NSLevelIndicator *levelIndicator;
@property (nonatomic,weak) IBOutlet NSTextField *label;
@end

@implementation AppDelegate

float normalizeVol(float volume)
{
    int volnorm = volume*100;
    if(volnorm%5)
        volnorm += (volnorm%5>2.5?5-volnorm%5:-volnorm%5);
    
    return volnorm/100.0;
}

CGEventRef myCGEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *ref) {
    AppDelegate *self = (__bridge AppDelegate *)(ref);
    NSEvent* incomingEvent = [NSEvent eventWithCGEvent:event];
    NSUInteger flags = [incomingEvent modifierFlags] & NSDeviceIndependentModifierFlagsMask;

    NSPoint p = [incomingEvent locationInWindow];
    NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
    
    BOOL overMenuBar = !CGRectContainsPoint(screenFrame, p);
    
    if(flags == NSAlternateKeyMask || overMenuBar)
    {
        if (type==kCGEventScrollWheel)
        {
            float delta = [incomingEvent deltaY]>0?0.05:-0.05;
            
            float vol = normalizeVol([self volume]);
            float newvol = vol+delta;
            if(newvol<0)
                newvol=0;
            else if(newvol>1)
                newvol=1;
            
            [self setVolume: newvol];
        }
        else
        {
            [self toggleMute];
        }
        
        [self updateView];
        
        return NULL;
    }

    return event;    
}

- (void) updateView
{
    int vol = self.isMuted ? 0 : normalizeVol([self volume])*100;
    self.label.stringValue = [NSString stringWithFormat:@"%d%%",vol];
    self.levelIndicator.intValue = vol/(100/self.levelIndicator.maxValue);
    if(anim)
    {
        [anim stopAnimation];
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
    }
    self.window.alphaValue = 1;
    
    [self performSelector:@selector(fade) withObject:nil afterDelay:0.5];
    
    AudioServicesPlaySystemSound (sound);
}

- (void) fade
{
    anim = [[NSViewAnimation alloc] initWithDuration:1 animationCurve:NSAnimationLinear];
    [anim setAnimationBlockingMode:NSAnimationNonblocking];
    [anim setViewAnimations:@[@{NSViewAnimationTargetKey:self.window, NSViewAnimationEffectKey:NSViewAnimationFadeOutEffect}]];
    [anim startAnimation];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    id sndpath = [[NSBundle mainBundle] pathForResource:@"volume" ofType: @"aiff"];
    CFURLRef baseURL = (__bridge CFURLRef)[NSURL fileURLWithPath:sndpath];
    AudioServicesCreateSystemSoundID(baseURL, &sound);
    
    [self.window setLevel:NSFloatingWindowLevel];
    [self.window setStyleMask:NSBorderlessWindowMask];
    [self.window setOpaque:NO];
    [self.window setBackgroundColor:[NSColor clearColor]];
    
    NSView *view = self.window.contentView;
    CALayer *layer = [CALayer layer];
    layer.backgroundColor = CGColorCreateGenericRGB(0.0, 0.0, 0.0, 0.5);
    layer.cornerRadius = 20.0;
    layer.masksToBounds = YES;
    view.wantsLayer = YES;
    view.layer = layer;
    
    CFMachPortRef eventTap;
    CGEventMask eventMask;
    CFRunLoopSourceRef runLoopSource;
    eventMask = CGEventMaskBit(kCGEventScrollWheel) | CGEventMaskBit(kCGEventOtherMouseUp);
    eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                                kCGEventTapOptionDefault, eventMask, myCGEventCallback, (__bridge void *)(self));
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource,
                       kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);
    
    self.label.hidden = YES;
    self.window.alphaValue = 1;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.label.hidden = NO;
       [self updateView];
    });
}

- (float)volume
{
	Float32			outputVolume;
	
	UInt32 propertySize = 0;
	OSStatus status = noErr;
	AudioObjectPropertyAddress propertyAOPA;
	propertyAOPA.mElement = kAudioObjectPropertyElementMaster;
	propertyAOPA.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
	propertyAOPA.mScope = kAudioDevicePropertyScopeOutput;
	
	AudioDeviceID outputDeviceID = [self defaultOutputDeviceID];
    
	if (outputDeviceID == kAudioObjectUnknown)
	{
		NSLog(@"Unknown device");
		return 0.0;
	}
	
	if (!AudioHardwareServiceHasProperty(outputDeviceID, &propertyAOPA))
	{
		NSLog(@"No volume returned for device 0x%0x", outputDeviceID);
		return 0.0;
	}
	
	propertySize = sizeof(Float32);
	
	status = AudioHardwareServiceGetPropertyData(outputDeviceID, &propertyAOPA, 0, NULL, &propertySize, &outputVolume);
	
	if (status)
	{
		NSLog(@"No volume returned for device 0x%0x", outputDeviceID);
		return 0.0;
	}
	
	if (outputVolume < 0.0 || outputVolume > 1.0) return 0.0;
	
	return outputVolume;
}

- (UInt32) isMuted
{
    AudioDeviceID outputDeviceID = [self defaultOutputDeviceID];
    AudioObjectPropertyAddress propertyAOPA;
	propertyAOPA.mElement = kAudioObjectPropertyElementMaster;
	propertyAOPA.mScope = kAudioDevicePropertyScopeOutput;
    propertyAOPA.mSelector = kAudioDevicePropertyMute;
    
    UInt32 muted, size = sizeof(UInt32);
    
    AudioHardwareServiceGetPropertyData(outputDeviceID, &propertyAOPA, 0, NULL, &size, &muted);
    return muted;
}

- (void)toggleMute
{
    NSLog(@"Requested mute");
    
    AudioDeviceID outputDeviceID = [self defaultOutputDeviceID];
    AudioObjectPropertyAddress propertyAOPA;
	propertyAOPA.mElement = kAudioObjectPropertyElementMaster;
	propertyAOPA.mScope = kAudioDevicePropertyScopeOutput;
    propertyAOPA.mSelector = kAudioDevicePropertyMute;
    
    UInt32 mute = !self.isMuted;
    AudioHardwareServiceSetPropertyData(outputDeviceID, &propertyAOPA, 0, NULL, sizeof(UInt32), &mute);
}

// setting system volume - mutes if under threshhold
-(void)setVolume:(Float32)newVolume
{
    if (newVolume < 0.0 || newVolume > 1.0)
	{
		NSLog(@"Requested volume out of range (%.2f)", newVolume);
		return;
		
	}
    
	// get output device device
	UInt32 propertySize = 0;
	AudioObjectPropertyAddress propertyAOPA;
	propertyAOPA.mElement = kAudioObjectPropertyElementMaster;
	propertyAOPA.mScope = kAudioDevicePropertyScopeOutput;
	
    NSLog(@"Requested volume %.2f", newVolume);
    propertyAOPA.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
	
	AudioDeviceID outputDeviceID = [self defaultOutputDeviceID];
		
    AudioHardwareServiceSetPropertyData(outputDeviceID, &propertyAOPA, 0, NULL, sizeof(Float32), &newVolume);

    // make sure we're not muted
    propertyAOPA.mSelector = kAudioDevicePropertyMute;
    propertySize = sizeof(UInt32);
    UInt32 mute = 0;
    AudioHardwareServiceSetPropertyData(outputDeviceID, &propertyAOPA, 0, NULL, sizeof(UInt32), &mute);
    
    int vol = (int)[self volume]*100;
    self.label.stringValue = [NSString stringWithFormat:@"%d%%",vol];
    self.levelIndicator.intValue = vol;
}


-(AudioDeviceID)defaultOutputDeviceID
{
	AudioDeviceID	outputDeviceID = kAudioObjectUnknown;
	
	// get output device device
	UInt32 propertySize = 0;
	OSStatus status = noErr;
	AudioObjectPropertyAddress propertyAOPA;
	propertyAOPA.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAOPA.mElement = kAudioObjectPropertyElementMaster;
	propertyAOPA.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
	
	if (!AudioHardwareServiceHasProperty(kAudioObjectSystemObject, &propertyAOPA))
	{
		NSLog(@"Cannot find default output device!");
		return outputDeviceID;
	}
	
	propertySize = sizeof(AudioDeviceID);
	
	status = AudioHardwareServiceGetPropertyData(kAudioObjectSystemObject, &propertyAOPA, 0, NULL, &propertySize, &outputDeviceID);
	
	if(status)
	{
		NSLog(@"Cannot find default output device!");
	}
	return outputDeviceID;
}

@end