#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

FOUNDATION_EXPORT BOOL VoiceInputBuddyTryAudioOperation(void (^operation)(void));

FOUNDATION_EXPORT BOOL VoiceInputBuddyTryPlayAudioPlayerNode(AVAudioPlayerNode *player);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
