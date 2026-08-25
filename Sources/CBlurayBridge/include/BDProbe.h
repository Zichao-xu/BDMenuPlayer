#ifndef BDPROBE_H
#define BDPROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BDProbeResult BDProbeResult;

BDProbeResult *bdprobe_create(const char *disc_path);
void bdprobe_destroy(BDProbeResult *result);

const char *bdprobe_error(const BDProbeResult *result);
const char *bdprobe_disc_name(const BDProbeResult *result);
const char *bdprobe_volume_id(const BDProbeResult *result);
const char *bdprobe_libbluray_version(const BDProbeResult *result);

uint8_t bdprobe_is_bluray(const BDProbeResult *result);
uint8_t bdprobe_has_first_play(const BDProbeResult *result);
uint8_t bdprobe_has_top_menu(const BDProbeResult *result);
uint32_t bdprobe_title_count(const BDProbeResult *result);
uint32_t bdprobe_hdmv_title_count(const BDProbeResult *result);
uint32_t bdprobe_bdj_title_count(const BDProbeResult *result);
uint8_t bdprobe_bdj_detected(const BDProbeResult *result);
uint8_t bdprobe_bdj_handled(const BDProbeResult *result);
uint8_t bdprobe_aacs_detected(const BDProbeResult *result);
uint8_t bdprobe_aacs_handled(const BDProbeResult *result);
uint8_t bdprobe_bdplus_detected(const BDProbeResult *result);
uint8_t bdprobe_bdplus_handled(const BDProbeResult *result);
uint64_t bdprobe_main_duration_90k(const BDProbeResult *result);
uint32_t bdprobe_main_chapter_count(const BDProbeResult *result);
uint64_t bdprobe_main_chapter_start_90k(const BDProbeResult *result, uint32_t index);

#ifdef __cplusplus
}
#endif

#endif
