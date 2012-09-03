/*	Copyright � 2007 Apple Inc. All Rights Reserved.
	
	Disclaimer: IMPORTANT:  This Apple software is supplied to you by 
			Apple Inc. ("Apple") in consideration of your agreement to the
			following terms, and your use, installation, modification or
			redistribution of this Apple software constitutes acceptance of these
			terms.  If you do not agree with these terms, please do not use,
			install, modify or redistribute this Apple software.
			
			In consideration of your agreement to abide by the following terms, and
			subject to these terms, Apple grants you a personal, non-exclusive
			license, under Apple's copyrights in this original Apple software (the
			"Apple Software"), to use, reproduce, modify and redistribute the Apple
			Software, with or without modifications, in source and/or binary forms;
			provided that if you redistribute the Apple Software in its entirety and
			without modifications, you must retain this notice and the following
			text and disclaimers in all such redistributions of the Apple Software. 
			Neither the name, trademarks, service marks or logos of Apple Inc. 
			may be used to endorse or promote products derived from the Apple
			Software without specific prior written permission from Apple.  Except
			as expressly stated in this notice, no other rights or licenses, express
			or implied, are granted by Apple herein, including but not limited to
			any patent rights that may be infringed by your derivative works or by
			other works in which the Apple Software may be incorporated.
			
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
*/
/*=============================================================================
	AudioDevice.cpp
	
=============================================================================*/

#include "AudioDevice.h"
#import <Cocoa/Cocoa.h>

char *OSTStr( OSType type )
{ static union OSTStr {
		uint32_t four;
		char str[5];
  } ltype;
	ltype.four = EndianU32_BtoN(type);
	ltype.str[4] = '\0';
	return ltype.str;
}

OSStatus DefaultListener( AudioDeviceID inDevice, UInt32 inChannel, Boolean isInput,
					AudioDevicePropertyID inPropertyID,
					void* inClientData)
{ UInt32 size;
  Float64 sampleRate;
  AudioDevice *dev = (AudioDevice*) inClientData;
  NSString *msg = [[NSString alloc] initWithFormat:@"Property %s(%u) of device %u[%u] changed; data=%p",
		   OSTStr((OSType)inPropertyID), (unsigned int) inPropertyID, (unsigned int)inDevice, (unsigned int)inChannel, inClientData ];
	switch( inPropertyID ){
		case kAudioDevicePropertyNominalSampleRate:
			size = sizeof(Float64);
			if( AudioDeviceGetProperty( inDevice, 0, isInput, kAudioDevicePropertyNominalSampleRate, &size, &sampleRate ) == noErr
			   && (dev && dev->listenerVerbose)
			){
				NSLog( @"%@\n\tkAudioDevicePropertyNominalSampleRate=%g\n", msg, sampleRate );
			}
			break;
		case kAudioDevicePropertyActualSampleRate:
			size = sizeof(Float64);
			if( AudioDeviceGetProperty( inDevice, 0, isInput, kAudioDevicePropertyActualSampleRate, &size, &sampleRate ) == noErr
			   && (dev && dev->listenerVerbose)
			){
				NSLog( @"%@\n\tkAudioDevicePropertyActualSampleRate=%g\n", msg, sampleRate );
			}
			break;
		default:
			if( (dev && dev->listenerVerbose) ){
				NSLog(msg);
			}
			break;
	}
	dev->listenerVerbose = true;
	return noErr;		
}

void	AudioDevice::Init(AudioDevicePropertyListenerProc lProc=DefaultListener)
{  UInt32 propsize;

	if (mID == kAudioDeviceUnknown) return;

	propsize = sizeof(UInt32);
	verify_noerr(AudioDeviceGetProperty(mID, 0, mIsInput, kAudioDevicePropertySafetyOffset, &propsize, &mSafetyOffset));

	propsize = sizeof(UInt32);
	verify_noerr(AudioDeviceGetProperty(mID, 0, mIsInput, kAudioDevicePropertyBufferFrameSize, &propsize, &mBufferSizeFrames));

	listenerProc = lProc;
	listenerVerbose = true;
	AudioDeviceAddPropertyListener( mID, 0, false, kAudioDevicePropertyActualSampleRate, lProc, this );
	AudioDeviceAddPropertyListener( mID, 0, false, kAudioDevicePropertyNominalSampleRate, lProc, this );
	AudioDeviceAddPropertyListener( mID, 0, false, kAudioDevicePropertyStreamFormat, lProc, this );
	AudioDeviceAddPropertyListener( mID, 0, false, kAudioDevicePropertyBufferFrameSize, lProc, this );
	propsize = sizeof(Float64);
	verify_noerr( AudioDeviceGetProperty( mID, 0, mIsInput, kAudioDevicePropertyNominalSampleRate, &propsize, &currentNominalSR ) );
	propsize = sizeof(AudioStreamBasicDescription);
	verify_noerr(AudioDeviceGetProperty(mID, 0, mIsInput, kAudioDevicePropertyStreamFormat, &propsize, &mInitialFormat));
	mFormat = mInitialFormat;
	propsize = 0;
	if( AudioDeviceGetProperty( mID, 0, false, kAudioDevicePropertyAvailableNominalSampleRates, &propsize, NULL ) == noErr ){
		if( propsize == 0 ){
			propsize = 100 * sizeof(AudioValueRange);
		}
		if( (nominalSampleRateList = (AudioValueRange*) calloc( 1, propsize )) ){
		  OSStatus err = AudioDeviceGetProperty( mID, 0, false, kAudioDevicePropertyAvailableNominalSampleRates, &propsize, nominalSampleRateList );
			if( err ){
				free( nominalSampleRateList );
			}
			else{
			  UInt32 i;
			  char name[256];
				if( propsize != 100 * sizeof(AudioValueRange) ){
					nominalSampleRateList = (AudioValueRange*) realloc( nominalSampleRateList, propsize );
				}
				nominalSampleRates = propsize / sizeof(AudioValueRange);
				minNominalSR = nominalSampleRateList[0].mMinimum;
				maxNominalSR = nominalSampleRateList[0].mMaximum;
				for( i = 1 ; i < nominalSampleRates ; i++ ){
					if( minNominalSR > nominalSampleRateList[i].mMinimum ){
						minNominalSR = nominalSampleRateList[i].mMinimum;
					}
					if( maxNominalSR < nominalSampleRateList[i].mMaximum ){
						maxNominalSR = nominalSampleRateList[i].mMaximum;
					}
				}
				name[0] = '\0';
				GetName( name, sizeof(name) );
				NSLog( @"Using audio device %u \"%s\", sample rate range [%g,%g]", mID, name, minNominalSR, maxNominalSR );
			}
		}
	}
}

AudioDevice::AudioDevice()
	:mID(kAudioDeviceUnknown)
	,mIsInput(false)
{
	listenerProc = NULL;
}

AudioDevice::AudioDevice(AudioDeviceID devid, bool isInput)
	:mID(devid)
	,mIsInput(isInput)
{
	Init(DefaultListener);
}

AudioDevice::AudioDevice(AudioDeviceID devid, bool isInput, AudioDevicePropertyListenerProc lProc)
	:mID(devid)
	,mIsInput(isInput)
{
	Init(lProc);
}

AudioDevice::~AudioDevice()
{
	if( mID != kAudioDeviceUnknown ){
//	  UInt32 propsize = sizeof(AudioStreamBasicDescription);
	  OSStatus err;
		// RJVB 20120902: setting the StreamFormat to the initially read values will set the channel bitdepth to 16??
//		err = AudioDeviceSetProperty(mID, NULL, 0, mIsInput, kAudioDevicePropertyStreamFormat, propsize, &mInitialFormat);
		err = SetNominalSampleRate(mInitialFormat.mSampleRate);
		if( err != noErr ){
		  char devName[256];
			GetName( devName, sizeof(devName) );
			fprintf( stderr, "Cannot reset initial settings for device %u (%s): err %4.4s, %ld\n",
				   mID, devName, (char*)&err, err );
		}
		if( listenerProc ){
			AudioDeviceRemovePropertyListener( mID, 0, false, kAudioDevicePropertyActualSampleRate, listenerProc );
			AudioDeviceRemovePropertyListener( mID, 0, false, kAudioDevicePropertyNominalSampleRate, listenerProc );
			AudioDeviceRemovePropertyListener( mID, 0, false, kAudioDevicePropertyStreamFormat, listenerProc );
			AudioDeviceRemovePropertyListener( mID, 0, false, kAudioDevicePropertyBufferFrameSize, listenerProc );
		}
		if( nominalSampleRateList ){
			free(nominalSampleRateList);
		}
	}
}

void	AudioDevice::SetBufferSize(UInt32 size)
{
	UInt32 propsize = sizeof(UInt32);
	verify_noerr(AudioDeviceSetProperty(mID, NULL, 0, mIsInput, kAudioDevicePropertyBufferFrameSize, propsize, &size));

	propsize = sizeof(UInt32);
	verify_noerr(AudioDeviceGetProperty(mID, 0, mIsInput, kAudioDevicePropertyBufferFrameSize, &propsize, &mBufferSizeFrames));
}

OSStatus AudioDevice::NominalSampleRate(Float64 &sampleRate)
{ UInt32 size = sizeof(Float64);
  OSStatus err;
  listenerVerbose = false;
  err = AudioDeviceGetProperty( mID, 0, mIsInput, kAudioDevicePropertyNominalSampleRate, &size, &sampleRate );
  if( err == noErr ){
	  currentNominalSR = sampleRate;
  }
  return err;
}

OSStatus AudioDevice::SetNominalSampleRate(Float64 sampleRate, Boolean force)
{ UInt32 size = sizeof(Float64);
  OSStatus err;
	listenerVerbose = false;
	while( sampleRate < minNominalSR && sampleRate*2 <= maxNominalSR ){
		sampleRate *= 2;
		listenerVerbose = true;
	}
	while( sampleRate > maxNominalSR && sampleRate/2 >= minNominalSR ){
		sampleRate /= 2;
		listenerVerbose = true;
	}
	if( sampleRate != currentNominalSR || force ){
		err = AudioDeviceSetProperty( mID, NULL, 0, mIsInput, kAudioDevicePropertyNominalSampleRate, size, &sampleRate );
		if( err == noErr ){
			currentNominalSR = sampleRate;
		}
	}
	else{
		err = noErr;
	}
	return err;
}

OSStatus AudioDevice::ResetNominalSampleRate(Boolean force)
{ UInt32 size = sizeof(Float64);
  Float64 sampleRate = mInitialFormat.mSampleRate;
  OSStatus err = noErr;
	if( sampleRate != currentNominalSR || force ){
		listenerVerbose = false;
		err = AudioDeviceSetProperty( mID, NULL, 0, mIsInput, kAudioDevicePropertyNominalSampleRate, size, &sampleRate );
		if( err == noErr ){
			currentNominalSR = sampleRate;
		}
	}
	return err;
}

OSStatus AudioDevice::SetStreamBasicDescription(AudioStreamBasicDescription *desc)
{ UInt32 size = sizeof(AudioStreamBasicDescription);
  OSStatus err;
	listenerVerbose = false;
	err = AudioDeviceSetProperty( mID, NULL, 0, mIsInput, kAudioDevicePropertyStreamFormat, size, desc );
	if( err == noErr ){
		currentNominalSR = desc->mSampleRate;
	}
	return err;
}

int AudioDevice::CountChannels()
{ OSStatus err;
  UInt32 propSize;
  int result = 0;
	
	err = AudioDeviceGetPropertyInfo(mID, 0, mIsInput, kAudioDevicePropertyStreamConfiguration, &propSize, NULL);
	if (err) return 0;

	AudioBufferList *buflist = (AudioBufferList *)malloc(propSize);
	err = AudioDeviceGetProperty(mID, 0, mIsInput, kAudioDevicePropertyStreamConfiguration, &propSize, buflist);
	if (!err) {
		for (UInt32 i = 0; i < buflist->mNumberBuffers; ++i) {
			result += buflist->mBuffers[i].mNumberChannels;
		}
	}
	free(buflist);
	return result;
}

char *AudioDevice::GetName(char *buf, UInt32 maxlen)
{
	verify_noerr(AudioDeviceGetProperty(mID, 0, mIsInput, kAudioDevicePropertyDeviceName, &maxlen, buf));
	return buf;
}

AudioDevice *GetDefaultDevice(Boolean isInput, OSStatus &err, AudioDevice *dev)
{ UInt32 propsize, defaultDeviceID;

	propsize = sizeof(AudioDeviceID);
	if( isInput ){
		err = AudioHardwareGetProperty(kAudioHardwarePropertyDefaultInputDevice, &propsize, &defaultDeviceID);
	}
	else{
		err = AudioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice, &propsize, &defaultDeviceID);
	}
	if( err == noErr ){
		if( dev ){
			if( dev->mID != defaultDeviceID ){
				delete dev;
			}
			else{
				goto bail;
			}
		}
		dev = new AudioDevice( defaultDeviceID, isInput );
		if( !dev ){
			err = MemError();
		}
	}
bail:
	return dev;
}
