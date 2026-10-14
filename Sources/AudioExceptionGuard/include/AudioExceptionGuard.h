#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL VoiceInputBuddyTryAudioOperation(void (^operation)(void));

FOUNDATION_EXPORT BOOL VoiceInputBuddyTryPlayAudioPlayerNode(AVAudioPlayerNode *player);

NS_ASSUME_NONNULL_END
