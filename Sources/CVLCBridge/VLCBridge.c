#include "VLCBridge.h"

#include <vlc/vlc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct VLCBridge {
    libvlc_instance_t *instance;
    libvlc_media_player_t *player;
    libvlc_media_t *media;
    void *video_view;
    char error[512];
};

static void set_error(VLCBridge *bridge, const char *fallback) {
    if (!bridge) {
        return;
    }
    const char *vlc_error = libvlc_errmsg();
    snprintf(bridge->error, sizeof(bridge->error), "%s", vlc_error ? vlc_error : fallback);
}

VLCBridge *vlcbridge_create(const char *plugin_path) {
    VLCBridge *bridge = calloc(1, sizeof(VLCBridge));
    if (!bridge) {
        return NULL;
    }

    if (plugin_path && plugin_path[0]) {
        setenv("VLC_PLUGIN_PATH", plugin_path, 1);
    }
    const char *arguments[] = {
        "--no-video-title-show",
        "--no-snapshot-preview",
        "--no-osd"
    };

    bridge->instance = libvlc_new(3, arguments);
    if (!bridge->instance) {
        free(bridge);
        return NULL;
    }

    bridge->player = libvlc_media_player_new(bridge->instance);
    if (!bridge->player) {
        set_error(bridge, "Unable to create libVLC media player");
    }
    return bridge;
}

void vlcbridge_destroy(VLCBridge *bridge) {
    if (!bridge) {
        return;
    }
    if (bridge->player) {
        libvlc_media_player_stop(bridge->player);
        libvlc_media_player_release(bridge->player);
    }
    if (bridge->media) {
        libvlc_media_release(bridge->media);
    }
    if (bridge->instance) {
        libvlc_release(bridge->instance);
    }
    free(bridge);
}

void vlcbridge_set_video_view(VLCBridge *bridge, void *nsview) {
    if (!bridge || !bridge->player) {
        return;
    }
    bridge->video_view = nsview;
    libvlc_media_player_set_nsobject(bridge->player, nsview);
    libvlc_video_set_mouse_input(bridge->player, true);
    libvlc_video_set_key_input(bridge->player, true);
}

int vlcbridge_play_bluray(VLCBridge *bridge, const char *disc_path, const char *subtitle_uri) {
    if (!bridge || !bridge->instance || !bridge->player || !disc_path) {
        return -1;
    }

    libvlc_media_player_stop(bridge->player);
    if (bridge->media) {
        libvlc_media_release(bridge->media);
        bridge->media = NULL;
    }

    size_t mrl_length = strlen(disc_path) + 16;
    char *mrl = malloc(mrl_length);
    if (!mrl) {
        set_error(bridge, "Unable to allocate Blu-ray location");
        return -1;
    }
    snprintf(mrl, mrl_length, "bluray://%s", disc_path);
    bridge->media = libvlc_media_new_location(bridge->instance, mrl);
    free(mrl);

    if (!bridge->media) {
        set_error(bridge, "Unable to create Blu-ray media");
        return -1;
    }

    libvlc_media_add_option(bridge->media, ":bluray-menu");
    if (subtitle_uri && subtitle_uri[0]) {
        if (libvlc_media_slaves_add(
            bridge->media,
            libvlc_media_slave_type_subtitle,
            4,
            subtitle_uri
        ) != 0) {
            set_error(bridge, "Unable to attach external subtitle");
            return -1;
        }
    }

    libvlc_media_player_set_media(bridge->player, bridge->media);

    int status = libvlc_media_player_play(bridge->player);
    if (status != 0) {
        set_error(bridge, "Blu-ray playback failed");
    }
    return status;
}

int vlcbridge_add_subtitle(VLCBridge *bridge, const char *subtitle_uri) {
    if (!bridge || !bridge->player || !subtitle_uri) {
        return -1;
    }
    int status = libvlc_media_player_add_slave(
        bridge->player,
        libvlc_media_slave_type_subtitle,
        subtitle_uri,
        true
    );
    if (status != 0) {
        set_error(bridge, "Unable to load external subtitle");
    }
    return status;
}

void vlcbridge_stop(VLCBridge *bridge) {
    if (bridge && bridge->player) {
        libvlc_media_player_stop(bridge->player);
    }
}

void vlcbridge_toggle_pause(VLCBridge *bridge) {
    if (bridge && bridge->player) {
        libvlc_media_player_pause(bridge->player);
    }
}

void vlcbridge_navigate(VLCBridge *bridge, VLCBridgeNavigation navigation) {
    if (!bridge || !bridge->player) {
        return;
    }
    libvlc_navigate_mode_t mode = libvlc_navigate_activate;
    switch (navigation) {
        case VLCBridgeNavigateUp: mode = libvlc_navigate_up; break;
        case VLCBridgeNavigateDown: mode = libvlc_navigate_down; break;
        case VLCBridgeNavigateLeft: mode = libvlc_navigate_left; break;
        case VLCBridgeNavigateRight: mode = libvlc_navigate_right; break;
        case VLCBridgeNavigatePopup: mode = libvlc_navigate_popup; break;
        case VLCBridgeNavigateActivate: mode = libvlc_navigate_activate; break;
    }
    libvlc_media_player_navigate(bridge->player, mode);
}

int vlcbridge_player_state(const VLCBridge *bridge) {
    if (!bridge || !bridge->player) {
        return libvlc_Error;
    }
    return (int)libvlc_media_player_get_state(bridge->player);
}

int vlcbridge_has_video_output(const VLCBridge *bridge) {
    if (!bridge || !bridge->player) {
        return 0;
    }
    return libvlc_media_player_has_vout(bridge->player) > 0;
}

int64_t vlcbridge_player_time(const VLCBridge *bridge) {
    if (!bridge || !bridge->player) {
        return -1;
    }
    return libvlc_media_player_get_time(bridge->player);
}

int64_t vlcbridge_player_length(const VLCBridge *bridge) {
    if (!bridge || !bridge->player) {
        return -1;
    }
    return libvlc_media_player_get_length(bridge->player);
}

void vlcbridge_set_player_time(VLCBridge *bridge, int64_t milliseconds) {
    if (bridge && bridge->player) {
        libvlc_media_player_set_time(bridge->player, milliseconds);
    }
}

void vlcbridge_previous_chapter(VLCBridge *bridge) {
    if (bridge && bridge->player) {
        libvlc_media_player_previous_chapter(bridge->player);
    }
}

void vlcbridge_next_chapter(VLCBridge *bridge) {
    if (bridge && bridge->player) {
        libvlc_media_player_next_chapter(bridge->player);
    }
}

int vlcbridge_audio_volume(const VLCBridge *bridge) {
    return bridge && bridge->player ? libvlc_audio_get_volume(bridge->player) : 100;
}

void vlcbridge_set_audio_volume(VLCBridge *bridge, int volume) {
    if (bridge && bridge->player) {
        libvlc_audio_set_volume(bridge->player, volume);
    }
}

int vlcbridge_audio_muted(const VLCBridge *bridge) {
    return bridge && bridge->player ? libvlc_audio_get_mute(bridge->player) : 0;
}

void vlcbridge_toggle_audio_mute(VLCBridge *bridge) {
    if (bridge && bridge->player) {
        libvlc_audio_toggle_mute(bridge->player);
    }
}

int vlcbridge_subtitle_track_count(const VLCBridge *bridge) {
    if (!bridge || !bridge->player) {
        return -1;
    }
    return libvlc_video_get_spu_count(bridge->player);
}

const char *vlcbridge_last_error(const VLCBridge *bridge) {
    if (!bridge || !bridge->error[0]) {
        return NULL;
    }
    return bridge->error;
}
