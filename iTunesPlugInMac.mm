//
// File:       iTunesPlugInMac.mm
//
// Abstract:   Visual plug-in for iTunes on MacOS
//
// Version:    2.0
//
// Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple Inc. ( "Apple" )
//             in consideration of your agreement to the following terms, and your use,
//             installation, modification or redistribution of this Apple software
//             constitutes acceptance of these terms.  If you do not agree with these
//             terms, please do not use, install, modify or redistribute this Apple
//             software.
//
//             In consideration of your agreement to abide by the following terms, and
//             subject to these terms, Apple grants you a personal, non - exclusive
//             license, under Apple's copyrights in this original Apple software ( the
//             "Apple Software" ), to use, reproduce, modify and redistribute the Apple
//             Software, with or without modifications, in source and / or binary forms;
//             provided that if you redistribute the Apple Software in its entirety and
//             without modifications, you must retain this notice and the following text
//             and disclaimers in all such redistributions of the Apple Software. Neither
//             the name, trademarks, service marks or logos of Apple Inc. may be used to
//             endorse or promote products derived from the Apple Software without specific
//             prior written permission from Apple.  Except as expressly stated in this
//             notice, no other rights or licenses, express or implied, are granted by
//             Apple herein, including but not limited to any patent rights that may be
//             infringed by your derivative works or by other works in which the Apple
//             Software may be incorporated.
//
//             The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
//             WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
//             WARRANTIES OF NON - INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A
//             PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION
//             ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
//
//             IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
//             CONSEQUENTIAL DAMAGES ( INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//             SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//             INTERRUPTION ) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION
//             AND / OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER
//             UNDER THEORY OF CONTRACT, TORT ( INCLUDING NEGLIGENCE ), STRICT LIABILITY OR
//             OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// Copyright © 2001-2011 Apple Inc. All Rights Reserved.
//

//-------------------------------------------------------------------------------------------------
//	includes
//-------------------------------------------------------------------------------------------------

#import "iTunesPlugIn.h"

#import <AppKit/AppKit.h>
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#import <string.h>
#import <stdarg.h>

//-------------------------------------------------------------------------------------------------
//	constants, etc.
//-------------------------------------------------------------------------------------------------

#define kTVisualPluginName              CFSTR("iTunes BitPerfect SampleRate")

//-------------------------------------------------------------------------------------------------
//	exported function prototypes
//-------------------------------------------------------------------------------------------------

extern "C" OSStatus iTunesPluginMainMachO( OSType inMessage, PluginMessageInfo *inMessageInfoPtr, void *refCon ) __attribute__((visibility("default")));

#if USE_SUBVIEW
//-------------------------------------------------------------------------------------------------
//	VisualView
//-------------------------------------------------------------------------------------------------

@interface VisualView : NSView
{
	BPPluginData *	_pluginData;
}

@property (nonatomic, assign) BPPluginData * pluginData;

-(void)drawRect:(NSRect)dirtyRect;
- (BOOL)acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
-(void)keyDown:(NSEvent *)theEvent;

@end

#endif	// USE_SUBVIEW

//-------------------------------------------------------------------------------------------------
//	DrawVisual
//-------------------------------------------------------------------------------------------------
//
void DrawVisual( BPPluginData * bpPluginData )
{
	CGRect			drawRect;
	CGPoint			where;

	// this shouldn't happen but let's be safe
	if ( bpPluginData->destView == NULL )
		return;

	drawRect = [bpPluginData->destView bounds];

	// fill the whole view with black to start
	[[NSColor blackColor] set];
	NSRectFill( drawRect );

	// pick a random location to draw our little square
	double			randomX = (random() / 2147483647.0);		// [0, 1]
	double			randomY = (random() / 2147483647.0);		// [0, 1]

	where.x = (CGFloat)(randomX * drawRect.size.width);
	where.y = (CGFloat)(randomY * drawRect.size.height);

	if ( bpPluginData->playing )
	{
		// if playing, draw a square whose color is dictated by the current max levels
		CGFloat		red		= (CGFloat)bpPluginData->maxLevel[1] / 256.0;
		CGFloat		green	= (CGFloat)bpPluginData->maxLevel[1] / 256.0;
		CGFloat		blue	= (CGFloat)bpPluginData->maxLevel[0] / 256.0;

		[[NSColor colorWithDeviceRed:red green:green blue:blue alpha:1] set];
	}
	else
	{
		// if idle, draw a partially transparent blue square
		[[[NSColor blueColor] colorWithAlphaComponent:0.75] set];
	}

	drawRect = NSMakeRect( where.x, where.y, 100, 100 );

	NSRectFill( drawRect );

	// should we draw the info/artwork in the bottom-left corner?
	time_t		theTime = time( NULL );

	if ( theTime < bpPluginData->drawInfoTimeOut )
	{
		where = CGPointMake( 10, 10 );

		// if we have a song title, draw it (prefer the stream title over the regular name if we have it)
		NSString *				theString = NULL;

		if ( bpPluginData->streamInfo.streamTitle[0] != 0 )
			theString = [NSString stringWithCharacters:&bpPluginData->streamInfo.streamTitle[1] length:bpPluginData->streamInfo.streamTitle[0]];
		else if ( bpPluginData->trackInfo.name[0] != 0 )
			theString = [NSString stringWithCharacters:&bpPluginData->trackInfo.name[1] length:bpPluginData->trackInfo.name[0]];
		
		if ( theString != NULL )
		{
			NSDictionary *		attrs = [NSDictionary dictionaryWithObjectsAndKeys:[NSColor whiteColor], NSForegroundColorAttributeName, NULL];
			
			[theString drawAtPoint:where withAttributes:attrs];
		}

		// draw the artwork
		if ( bpPluginData->currentArtwork != NULL )
		{
			where.y += 20;

			[bpPluginData->currentArtwork drawAtPoint:where fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:0.75];
		}
	}
}

//-------------------------------------------------------------------------------------------------
//	UpdateArtwork
//-------------------------------------------------------------------------------------------------
//
void UpdateArtwork( BPPluginData * bpPluginData, CFDataRef coverArt, UInt32 coverArtSize, UInt32 coverArtFormat )
{
	// release current image
	[bpPluginData->currentArtwork release];
	bpPluginData->currentArtwork = NULL;
	
	// create 100x100 NSImage* out of incoming CFDataRef if non-null (null indicates there is no artwork for the current track)
	if ( coverArt != NULL )
	{
		bpPluginData->currentArtwork = [[NSImage alloc] initWithData:(NSData *)coverArt];
		
		[bpPluginData->currentArtwork setSize:CGSizeMake( 100, 100 )];
	}
	
	UpdateInfoTimeOut( bpPluginData );
}

//-------------------------------------------------------------------------------------------------
//	InvalidateVisual
//-------------------------------------------------------------------------------------------------
//
void InvalidateVisual( BPPluginData * bpPluginData )
{
	(void) bpPluginData;

#if USE_SUBVIEW
	// when using a custom subview, we invalidate it so we get our own draw calls
	[bpPluginData->subview setNeedsDisplay:YES];
#endif
}

//-------------------------------------------------------------------------------------------------
//	CreateVisualContext
//-------------------------------------------------------------------------------------------------
//
OSStatus ActivateVisual( BPPluginData * bpPluginData, VISUAL_PLATFORM_VIEW destView, OptionBits options )
{
	OSStatus			status = noErr;

	bpPluginData->destView			= destView;
	bpPluginData->destRect			= [destView bounds];
	bpPluginData->destOptions		= options;

	UpdateInfoTimeOut( bpPluginData );

#if USE_SUBVIEW

	// NSView-based subview
	bpPluginData->subview = [[VisualView alloc] initWithFrame:bpPluginData->destRect];
	if( bpPluginData->subview != NULL ){
		[bpPluginData->subview setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];

		[bpPluginData->subview setPluginData:bpPluginData];

		[destView addSubview:bpPluginData->subview];
	}
	else{
		status = memFullErr;
	}

#endif

	return status;
}

//-------------------------------------------------------------------------------------------------
//	MoveVisual
//-------------------------------------------------------------------------------------------------
//
OSStatus MoveVisual( BPPluginData * bpPluginData, OptionBits newOptions )
{
	bpPluginData->destRect	  = [bpPluginData->destView bounds];
	bpPluginData->destOptions = newOptions;

	return noErr;
}

//-------------------------------------------------------------------------------------------------
//	DeactivateVisual
//-------------------------------------------------------------------------------------------------
//
OSStatus DeactivateVisual( BPPluginData * bpPluginData )
{
#if USE_SUBVIEW
	[bpPluginData->subview removeFromSuperview];
	[bpPluginData->subview autorelease];
	bpPluginData->subview = NULL;
	[bpPluginData->currentArtwork release];
	bpPluginData->currentArtwork = NULL;
#endif

	bpPluginData->destView			= NULL;
	bpPluginData->destRect			= CGRectNull;
	bpPluginData->drawInfoTimeOut	= 0;
	
	return noErr;
}

//-------------------------------------------------------------------------------------------------
//	ResizeVisual
//-------------------------------------------------------------------------------------------------
//
OSStatus ResizeVisual( BPPluginData * bpPluginData )
{
	bpPluginData->destRect = [bpPluginData->destView bounds];

	// note: the subview is automatically resized by iTunes so nothing to do here

	return noErr;
}

//-------------------------------------------------------------------------------------------------
//	ConfigureVisual
//-------------------------------------------------------------------------------------------------
//
OSStatus ConfigureVisual( BPPluginData * bpPluginData )
{
	(void) bpPluginData;

	// load nib
	// show modal dialog
	// update settings
	// invalidate

	return noErr;
}

#pragma mark -

#if USE_SUBVIEW

@implementation VisualView

@synthesize pluginData = _pluginData;

//-------------------------------------------------------------------------------------------------
//	isOpaque
//-------------------------------------------------------------------------------------------------
//
- (BOOL)isOpaque
{
	// your custom views should always be opaque or iTunes will waste CPU time drawing behind you
	return YES;
}

//-------------------------------------------------------------------------------------------------
//	drawRect
//-------------------------------------------------------------------------------------------------
//
-(void)drawRect:(NSRect)dirtyRect
{
	if ( _pluginData != NULL )
	{
		DrawVisual( _pluginData );
	}
}

//-------------------------------------------------------------------------------------------------
//	acceptsFirstResponder
//-------------------------------------------------------------------------------------------------
//
- (BOOL)acceptsFirstResponder
{
	return YES;
}

//-------------------------------------------------------------------------------------------------
//	becomeFirstResponder
//-------------------------------------------------------------------------------------------------
//
- (BOOL)becomeFirstResponder
{
	return YES;
}

//-------------------------------------------------------------------------------------------------
//	resignFirstResponder
//-------------------------------------------------------------------------------------------------
//
- (BOOL)resignFirstResponder
{
	return YES;
}

//-------------------------------------------------------------------------------------------------
//	keyDown
//-------------------------------------------------------------------------------------------------
//
-(void)keyDown:(NSEvent *)theEvent
{
	// Handle key events here.
	// Do not eat the space bar, ESC key, TAB key, or the arrow keys: iTunes reserves those keys.

	// if the 'i' key is pressed, reset the info timeout so that we draw it again
	if ( [[theEvent charactersIgnoringModifiers] isEqualTo:@"i"] )
	{
		UpdateInfoTimeOut( _pluginData );
		return;
	}

	// Pass all unhandled events up to super so that iTunes can handle them.
	[super keyDown:theEvent];
}

@end

#endif	// USE_SUBVIEW

#pragma mark -

//-------------------------------------------------------------------------------------------------
//	GetVisualName
//-------------------------------------------------------------------------------------------------
//
void GetVisualName( ITUniStr255 name )
{
	CFIndex length = CFStringGetLength( kTVisualPluginName );

	name[0] = (UniChar)length;
	CFStringGetCharacters( kTVisualPluginName, CFRangeMake( 0, length ), &name[1] );
}

//-------------------------------------------------------------------------------------------------
//	GetVisualOptions
//-------------------------------------------------------------------------------------------------
//
OptionBits GetVisualOptions( void )
{
	OptionBits		options = (kVisualSupportsMuxedGraphics | kVisualWantsIdleMessages | kVisualWantsConfigure);
	
#if USE_SUBVIEW
	options |= kVisualUsesSubview;
#endif

	return options;
}

void CFLog( const char *format, ... )
{ va_list ap;
	va_start( ap, format );
	NSLogv( [NSString stringWithFormat:@"%s",format], ap );
	va_end(ap);
}

//-------------------------------------------------------------------------------------------------
//	iTunesPluginMainMachO
//-------------------------------------------------------------------------------------------------
//
OSStatus iTunesPluginMainMachO( OSType message, PluginMessageInfo * messageInfo, void * refCon )
{
	OSStatus		status;
	
	(void) refCon;
	
	switch ( message )
	{
		case kPluginInitMessage:
			status = RegisterVisualPlugin( messageInfo );
			break;
			
		case kPluginCleanupMessage:
			NSLog( @"kPluginCleanupMessage" );
			status = noErr;
			break;
			
		default:
			status = unimpErr;
			break;
	}
	
	return status;
}