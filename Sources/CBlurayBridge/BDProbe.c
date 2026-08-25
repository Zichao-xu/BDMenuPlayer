#include "BDProbe.h"

#include <libbluray/bluray.h>
#include <libbluray/meta_data.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct BDProbeResult {
    char *error;
    char *disc_name;
    char *volume_id;
    char version[32];
    uint8_t is_bluray;
    uint8_t has_first_play;
    uint8_t has_top_menu;
    uint32_t title_count;
    uint32_t hdmv_title_count;
    uint32_t bdj_title_count;
    uint8_t bdj_detected;
    uint8_t bdj_handled;
    uint8_t aacs_detected;
    uint8_t aacs_handled;
    uint8_t bdplus_detected;
    uint8_t bdplus_handled;
    uint64_t main_duration_90k;
    uint32_t main_chapter_count;
    uint64_t *main_chapter_starts_90k;
};

static char *copy_string(const char *value) {
    return value ? strdup(value) : NULL;
}

BDProbeResult *bdprobe_create(const char *disc_path) {
    BDProbeResult *result = calloc(1, sizeof(BDProbeResult));
    if (!result) {
        return NULL;
    }

    int major = 0;
    int minor = 0;
    int micro = 0;
    bd_get_version(&major, &minor, &micro);
    snprintf(result->version, sizeof(result->version), "%d.%d.%d", major, minor, micro);

    if (!disc_path || !disc_path[0]) {
        result->error = copy_string("Missing Blu-ray path");
        return result;
    }

    BLURAY *bluray = bd_open(disc_path, NULL);
    if (!bluray) {
        result->error = copy_string("libbluray could not open this disc");
        return result;
    }

    const BLURAY_DISC_INFO *info = bd_get_disc_info(bluray);
    if (!info) {
        result->error = copy_string("No Blu-ray disc information was returned");
        bd_close(bluray);
        return result;
    }

    const META_DL *metadata = bd_get_meta(bluray);
    const char *metadata_name = metadata ? metadata->di_name : NULL;

    result->disc_name = copy_string(metadata_name ? metadata_name : info->disc_name);
    result->volume_id = copy_string(info->udf_volume_id);
    result->is_bluray = info->bluray_detected;
    result->has_first_play = info->first_play_supported;
    result->has_top_menu = info->top_menu_supported;
    result->title_count = info->num_titles;
    result->hdmv_title_count = info->num_hdmv_titles;
    result->bdj_title_count = info->num_bdj_titles;
    result->bdj_detected = info->bdj_detected;
    result->bdj_handled = info->bdj_handled;
    result->aacs_detected = info->aacs_detected;
    result->aacs_handled = info->aacs_handled;
    result->bdplus_detected = info->bdplus_detected;
    result->bdplus_handled = info->bdplus_handled;

    if (bd_get_titles(bluray, TITLES_ALL, 0) > 0) {
        int main_title = bd_get_main_title(bluray);
        if (main_title >= 0) {
            BLURAY_TITLE_INFO *title = bd_get_title_info(bluray, (uint32_t)main_title, 0);
            if (title) {
                result->main_duration_90k = title->duration;
                result->main_chapter_count = title->chapter_count;
                if (title->chapter_count > 0) {
                    result->main_chapter_starts_90k = calloc(title->chapter_count, sizeof(uint64_t));
                    if (result->main_chapter_starts_90k) {
                        for (uint32_t i = 0; i < title->chapter_count; i++) {
                            result->main_chapter_starts_90k[i] = title->chapters[i].start;
                        }
                    } else {
                        result->main_chapter_count = 0;
                    }
                }
                bd_free_title_info(title);
            }
        }
    }

    bd_close(bluray);
    return result;
}

void bdprobe_destroy(BDProbeResult *result) {
    if (!result) {
        return;
    }
    free(result->error);
    free(result->disc_name);
    free(result->volume_id);
    free(result->main_chapter_starts_90k);
    free(result);
}

#define STRING_GETTER(name, field) \
    const char *name(const BDProbeResult *result) { return result ? result->field : NULL; }

#define VALUE_GETTER(type, name, field) \
    type name(const BDProbeResult *result) { return result ? result->field : 0; }

STRING_GETTER(bdprobe_error, error)
STRING_GETTER(bdprobe_disc_name, disc_name)
STRING_GETTER(bdprobe_volume_id, volume_id)
STRING_GETTER(bdprobe_libbluray_version, version)

VALUE_GETTER(uint8_t, bdprobe_is_bluray, is_bluray)
VALUE_GETTER(uint8_t, bdprobe_has_first_play, has_first_play)
VALUE_GETTER(uint8_t, bdprobe_has_top_menu, has_top_menu)
VALUE_GETTER(uint32_t, bdprobe_title_count, title_count)
VALUE_GETTER(uint32_t, bdprobe_hdmv_title_count, hdmv_title_count)
VALUE_GETTER(uint32_t, bdprobe_bdj_title_count, bdj_title_count)
VALUE_GETTER(uint8_t, bdprobe_bdj_detected, bdj_detected)
VALUE_GETTER(uint8_t, bdprobe_bdj_handled, bdj_handled)
VALUE_GETTER(uint8_t, bdprobe_aacs_detected, aacs_detected)
VALUE_GETTER(uint8_t, bdprobe_aacs_handled, aacs_handled)
VALUE_GETTER(uint8_t, bdprobe_bdplus_detected, bdplus_detected)
VALUE_GETTER(uint8_t, bdprobe_bdplus_handled, bdplus_handled)
VALUE_GETTER(uint64_t, bdprobe_main_duration_90k, main_duration_90k)
VALUE_GETTER(uint32_t, bdprobe_main_chapter_count, main_chapter_count)

uint64_t bdprobe_main_chapter_start_90k(const BDProbeResult *result, uint32_t index) {
    if (!result || !result->main_chapter_starts_90k || index >= result->main_chapter_count) {
        return 0;
    }
    return result->main_chapter_starts_90k[index];
}
