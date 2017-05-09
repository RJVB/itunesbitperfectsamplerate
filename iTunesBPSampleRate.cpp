//
// @file		iTunesBPSampleRate.cpp
// Abstract:	A very simple (non) visual iTunes plugin that retrieves the sample rate of the
//			content being played and sets the hardware output device to that rate, if possible.
//			Output device changes are tracked when stopping and starting playback, and
//			under normal execution and termination the device is always returned to its
//			initial setting.
// Version:	1.0
// Copyright:	2012 RJVB

// Adapted from:
// File:       iTunesPlugIn.cpp
//
// Abstract:   Visual plug-in for iTunes.  Cross-platform code.
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

#include "iTunesPlugIn.h"

#include <string.h>
#include <wchar.h>

#include "AudioDevice.h"

typedef struct BPStruct {
	BPPluginData bpPluginData;
	AudioDevice *defaultADevice;
} BPStruct;

//-------------------------------------------------------------------------------------------------
//	UpdateInfoTimeOut
//-------------------------------------------------------------------------------------------------
//
void UpdateInfoTimeOut( BPPluginData * bpPluginData )
{
	// reset the timeout value we will use to show the info/artwork if we have it during DrawVisual()
	bpPluginData->drawInfoTimeOut = time( NULL ) + kInfoTimeOutInSeconds;
}

//-------------------------------------------------------------------------------------------------
//	UpdateTrackInfo
//-------------------------------------------------------------------------------------------------
//
void UpdateTrackInfo( BPStruct *bpData, ITTrackInfo * trackInfo, ITStreamInfo * streamInfo )
{ BPPluginData *bpPluginData = NULL;
	if( bpData ){
		bpPluginData = &bpData->bpPluginData;
		if( trackInfo->validFields & kITTISampleRateFieldMask ){
			bpData->defaultADevice->SetNominalSampleRate(trackInfo->sampleRateFloat);
		}
	}
	else{
		return;
	}
	if( trackInfo ){
		bpPluginData->trackInfo = *trackInfo;
	}
	else{
		memset( &bpPluginData->trackInfo, 0, sizeof(bpPluginData->trackInfo) );
	}
	if( streamInfo ){
		bpPluginData->streamInfo = *streamInfo;
	}
	else{
		memset( &bpPluginData->streamInfo, 0, sizeof(bpPluginData->streamInfo) );
	}

	UpdateInfoTimeOut( bpPluginData );
#ifdef DEBUG
	if( trackInfo ){
	  wchar_t fName[257];
		wmemcpy( (wchar_t*) fName, &((wchar_t*) trackInfo->fileName)[1], trackInfo->fileName[0] );
		fName[trackInfo->fileName[0]] = fName[255] = 0;
		CFLog( "%S: %g(%u)Hz, %u/%u tracks, %ukbps, %gs, %llu bytes",
			 fName, trackInfo->sampleRateFloat, trackInfo->oldSampleRateFixed,
			 trackInfo->trackNumber, trackInfo->numTracks, trackInfo->bitRate,
			 ((double)trackInfo->totalTimeInMS)/1000.0, trackInfo->sizeInBytes
		);
	}
#endif
}

//-------------------------------------------------------------------------------------------------
//	VisualPluginHandler
//-------------------------------------------------------------------------------------------------
//
static OSStatus VisualPluginHandler(OSType message, VisualPluginMessageInfo *messageInfo,void *refCon)
{
	OSStatus			status;
	BPPluginData *	bpPluginData;
	BPStruct			*bpData;

	bpData = (BPStruct*) refCon;
	if( bpData ){
		bpPluginData = &bpData->bpPluginData;
	}
	else{
		bpPluginData = NULL;
	}

	status = noErr;

	switch( message ){
		/*
			Sent when the visual plugin is registered.  The plugin should do minimal
			memory allocations here.
		*/		
		case kVisualPluginInitMessage:{
			if( bpData ){
				CFLog( "VisualPluginHandler: discarding entry bpData==%p", bpData );
			}
			bpData = (BPStruct *)calloc( 1, sizeof(BPStruct) );
			if ( bpData == NULL )
			{
				status = memFullErr;
				break;
			}

			bpPluginData = &bpData->bpPluginData;
			bpPluginData->appCookie	= messageInfo->u.initMessage.appCookie;
			bpPluginData->appProc	= messageInfo->u.initMessage.appProc;
			bpData->defaultADevice = GetDefaultDevice( false, status );

			messageInfo->u.initMessage.refCon = (void *)bpData;
			break;
		}
		/*
			Sent when the visual plugin is unloaded.
		*/		
		case kVisualPluginCleanupMessage:{
			if ( bpData != NULL ){
				delete bpData->defaultADevice;
				free( bpData );
			}
			CFLog( "kVisualPluginCleanupMessage" );
			break;
		}
		/*
			Sent when the visual plugin is enabled/disabled.  iTunes currently enables all
			loaded visual plugins at launch.  The plugin should not do anything here.
		*/
		case kVisualPluginEnableMessage:
#ifdef DEBUG
			CFLog( "kVisualPluginEnableMessage" );
#endif
			break;
		case kVisualPluginDisableMessage:{
			CFLog( "kVisualPluginDisableMessage" );
			break;
		}
		/*
			Sent if the plugin requests idle messages.  Do this by setting the kVisualWantsIdleMessages
			option in the RegisterVisualMessage.options field.
			
			DO NOT DRAW in this routine.  It is for updating internal state only.
		*/
		case kVisualPluginIdleMessage:{
			break;
		}			
		/*
			Sent if the plugin requests the ability for the user to configure it.  Do this by setting
			the kVisualWantsConfigure option in the RegisterVisualMessage.options field.
		*/
		case kVisualPluginConfigureMessage:{
            status = unimpErr;
			break;
		}
		/*
			Sent when iTunes is going to show the visual plugin.  At this
			point, the plugin should allocate any large buffers it needs.
		*/
		case kVisualPluginActivateMessage:{
            status = unimpErr;
			break;
		}	
		/*
			Sent when this visual is no longer displayed.
		*/
		case kVisualPluginDeactivateMessage:{
//			UpdateTrackInfo( bpData, NULL, NULL );
			CFLog( "kVisualPluginDeactivateMessage" );
            status = unimpErr;
			break;
		}
		/*
			Sent when iTunes is moving the destination view to a new parent window (e.g. to/from fullscreen).
		*/
		case kVisualPluginWindowChangedMessage:{
            status = unimpErr;
			break;
		}
		/*
			Sent when iTunes has changed the rectangle of the currently displayed visual.
			Note: for custom NSView subviews, the subview's frame is automatically resized.
		*/
		case kVisualPluginFrameChangedMessage:{
            status = unimpErr;
			break;
		}
		/*
			Sent for the visual plugin to update its internal animation state.
			Plugins are allowed to draw at this time but it is more efficient if they
			wait until the kVisualPluginDrawMessage is sent OR they simply invalidate
			their own subview.  The pulse message can be sent faster than the system
			will allow drawing to support spectral analysis-type plugins but drawing
			will be limited to the system refresh rate.
		*/
//		case kVisualPluginPulseMessage:{
//			break;
//		}
		/*
			It's time for the plugin to draw a new frame.
			
			For plugins using custom subviews, you should ignore this message and just
			draw in your view's draw method.  It will never be called if your subview 
			is set up properly.
		*/
		case kVisualPluginDrawMessage:{
			break;
		}
		/*
			Sent when the player starts.
		*/
		case kVisualPluginPlayMessage:{
			bpPluginData->playing = true;

			// reopen the default device if it has changed in the meantime:
			bpData->defaultADevice = GetDefaultDevice( false, status, bpData->defaultADevice );

			UpdateTrackInfo( bpData, messageInfo->u.playMessage.trackInfo, messageInfo->u.playMessage.streamInfo );
		
			break;
		}
		/*
			Sent when the player changes the current track information.  This
			is used when the information about a track changes.
		*/
        case kVisualPluginPulseMessage:
		case kVisualPluginChangeTrackMessage:{
			UpdateTrackInfo( bpData, messageInfo->u.changeTrackMessage.trackInfo, messageInfo->u.changeTrackMessage.streamInfo );

			break;
		}
		/*
			Artwork for the currently playing song is being delivered per a previous request.
			Note that NULL for messageInfo->u.coverArtMessage.coverArt means the currently playing song has no artwork.
		*/
		case kVisualPluginCoverArtMessage:{
            status = unimpErr;
			break;
		}
		/*
			Sent when the player stops or pauses.
		*/
		case kVisualPluginStopMessage:{
			bpPluginData->playing = false;
			
			if( bpData->defaultADevice ){
				bpData->defaultADevice->ResetNominalSampleRate();
				// reopen the default device if it has changed in the meantime:
				bpData->defaultADevice = GetDefaultDevice( false, status, bpData->defaultADevice );
			}
			break;
		}
		/*
			Sent when the player changes the playback position.
		*/
		case kVisualPluginSetPositionMessage:{
            status = unimpErr;
			break;
		}
		default:{
			status = unimpErr;
			break;
		}
	}

	return status;	
}

//-------------------------------------------------------------------------------------------------
//	RegisterVisualPlugin
//-------------------------------------------------------------------------------------------------
//
OSStatus RegisterVisualPlugin( PluginMessageInfo *messageInfo, PlayerMessageInfo &playerMessageInfo )
{ OSStatus status;
		
	memset( &playerMessageInfo.u.registerVisualPluginMessage, 0, sizeof(playerMessageInfo.u.registerVisualPluginMessage) );

	GetVisualName( playerMessageInfo.u.registerVisualPluginMessage.name );

	SetNumVersion( &playerMessageInfo.u.registerVisualPluginMessage.pluginVersion, kTVisualPluginMajorVersion, kTVisualPluginMinorVersion, kTVisualPluginReleaseStage, kTVisualPluginNonFinalRelease );

	playerMessageInfo.u.registerVisualPluginMessage.options			= 0; /*GetVisualOptions();*/
	playerMessageInfo.u.registerVisualPluginMessage.handler			= (VisualPluginProcPtr)VisualPluginHandler;
	playerMessageInfo.u.registerVisualPluginMessage.registerRefCon		= 0;
	playerMessageInfo.u.registerVisualPluginMessage.creator			= kTVisualPluginCreator;
	
	playerMessageInfo.u.registerVisualPluginMessage.pulseRateInHz		= kStoppedPulseRateInHz;	// update my state N times a second
	playerMessageInfo.u.registerVisualPluginMessage.numWaveformChannels	= 0;
	playerMessageInfo.u.registerVisualPluginMessage.numSpectrumChannels	= 0;
	
	playerMessageInfo.u.registerVisualPluginMessage.minWidth			= 64;
	playerMessageInfo.u.registerVisualPluginMessage.minHeight			= 64;
	playerMessageInfo.u.registerVisualPluginMessage.maxWidth			= 0;	// no max width limit
	playerMessageInfo.u.registerVisualPluginMessage.maxHeight			= 0;	// no max height limit
	
	status = PlayerRegisterVisualPlugin( messageInfo->u.initMessage.appCookie, messageInfo->u.initMessage.appProc, &playerMessageInfo );
		
	return status;
}
