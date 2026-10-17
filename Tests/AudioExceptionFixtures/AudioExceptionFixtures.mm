#import "AudioExceptionFixtures.h"
#import "AudioExceptionGuard.h"
#include <stdexcept>

BOOL AudioFixtureCatchesCppException(void) {
    return !VoiceInputBuddyTryAudioOperation(^{ throw std::runtime_error("fixture"); });
}
