#import "AudioExceptionGuard.h"

BOOL VoiceInputBuddyTryAudioOperation(void (^operation)(void)) {
    try {
        @try {
            operation();
            return YES;
        } @catch (__unused NSException *exception) {
            return NO;
        }
    } catch (...) {
        return NO;
    }
}

BOOL VoiceInputBuddyTryPlayAudioPlayerNode(AVAudioPlayerNode *player) {
    return VoiceInputBuddyTryAudioOperation(^{ [player play]; });
}
