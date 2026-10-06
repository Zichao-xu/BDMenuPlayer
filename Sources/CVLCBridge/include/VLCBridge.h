#ifndef VLCBRIDGE_H
#define VLCBRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VLCBridge VLCBridge;

typedef enum VLCBridgeNavigation {
    VLCBridgeNavigateActivate = 0,
    VLCBridgeNavigateUp = 1,
    VLCBridgeNavigateDown = 2,
    VLCBridgeNavigateLeft = 3,
    VLCBridgeNavigateRight = 4,
    VLCBridgeNavigatePopup = 5
} VLCBridgeNavigation;

VLCBridge *vlcbridge_create(const char *plugin_path);
void vlcbridge_destroy(VLCBridge *bridge);

void vlcbridge_set_video_view(VLCBridge *bridge, void *nsview);
int vlcbridge_play_bluray(VLCBridge *bridge, const char *disc_path, const char *subtitle_uri);
int vlcbridge_add_subtitle(VLCBridge *bridge, const char *subtitle_uri);
void vlcbridge_stop(VLCBridge *bridge);
void vlcbridge_toggle_pause(VLCBridge *bridge);
void vlcbridge_navigate(VLCBridge *bridge, VLCBridgeNavigation navigation);
int vlcbridge_player_state(const VLCBridge *bridge);
int vlcbridge_has_video_output(const VLCBridge *bridge);
int64_t vlcbridge_player_time(const VLCBridge *bridge);
int64_t vlcbridge_player_length(const VLCBridge *bridge);
void vlcbridge_set_player_time(VLCBridge *bridge, int64_t milliseconds);
void vlcbridge_previous_chapter(VLCBridge *bridge);
void vlcbridge_next_chapter(VLCBridge *bridge);
int vlcbridge_audio_volume(const VLCBridge *bridge);
void vlcbridge_set_audio_volume(VLCBridge *bridge, int volume);
int vlcbridge_audio_muted(const VLCBridge *bridge);
void vlcbridge_toggle_audio_mute(VLCBridge *bridge);
int vlcbridge_subtitle_track_count(const VLCBridge *bridge);

const char *vlcbridge_last_error(const VLCBridge *bridge);
size_t vlcbridge_copy_log_errors(VLCBridge *bridge, char *buffer, size_t length);

#ifdef __cplusplus
}
#endif

#endif
