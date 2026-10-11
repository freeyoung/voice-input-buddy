#import "AudioExceptionGuard.h"

BOOL VoiceInputBuddyTryPlayAudioPlayerNode(AVAudioPlayerNode *player) {
    @try {
        [player play];
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}
