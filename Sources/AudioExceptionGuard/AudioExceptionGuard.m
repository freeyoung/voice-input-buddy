#import "AudioExceptionGuard.h"

BOOL VoiceInputBuddyTryAudioOperation(void (^operation)(void)) {
    @try {
        operation();
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

BOOL VoiceInputBuddyTryPlayAudioPlayerNode(AVAudioPlayerNode *player) {
    return VoiceInputBuddyTryAudioOperation(^{ [player play]; });
}
