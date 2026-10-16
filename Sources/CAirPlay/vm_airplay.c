// Thin wrapper around UxPlay's lib/ (GPL-3.0): one mirroring receiver per process.
// Mirrors the setup in UxPlay's uxplay.cpp (start_dnssd, start_raop_server, register_dnssd).

#include "vm_airplay.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "uxplay/lib/dnssd.h"
#include "uxplay/lib/logger.h"
#include "uxplay/lib/raop.h"
#include "uxplay/lib/stream.h"

static raop_t *g_raop = NULL;
static dnssd_t *g_dnssd = NULL;
static vm_airplay_callbacks g_cb;

// MARK: - raop callbacks

static void cb_video_process(void *cls, raop_ntp_t *ntp, video_decode_struct *data) {
    if (g_cb.video_frame) g_cb.video_frame(g_cb.ctx, data->data, data->data_len, data->is_h265);
}

static void cb_audio_process(void *cls, raop_ntp_t *ntp, audio_decode_struct *data) {
    if (g_cb.audio_packet) g_cb.audio_packet(g_cb.ctx, data->data, data->data_len);
}

static void cb_audio_get_format(void *cls, unsigned char *ct, unsigned short *spf, bool *using_screen,
                                bool *is_media, uint64_t *audio_format) {
    if (g_cb.audio_format) g_cb.audio_format(g_cb.ctx, *ct, *spf);
}

static void cb_audio_set_volume(void *cls, float volume) {
    if (g_cb.audio_volume) g_cb.audio_volume(g_cb.ctx, volume);
}

static void cb_report_client_request(void *cls, char *deviceid, char *model, char *name, bool *admit) {
    *admit = true;
    if (g_cb.client_connected) g_cb.client_connected(g_cb.ctx, name ? name : "", model ? model : "");
}

static void cb_mirror_video_running(void *cls, bool running) {
    if (g_cb.mirror_running) g_cb.mirror_running(g_cb.ctx, running);
}

static void cb_conn_feedback(void *cls) {
    if (g_cb.heartbeat) g_cb.heartbeat(g_cb.ctx);
}

static void cb_conn_reset(void *cls, int reason) {
    if (g_cb.connection_lost) g_cb.connection_lost(g_cb.ctx);
}

static void cb_video_reset(void *cls, reset_type_t type) {
    if (type != RESET_TYPE_ON_VIDEO_PLAY && g_cb.mirror_running) g_cb.mirror_running(g_cb.ctx, false);
}

static void cb_log(void *cls, int level, const char *msg) {
    if (g_cb.log) g_cb.log(g_cb.ctx, level, msg);
}

static int cb_video_set_codec(void *cls, video_codec_t codec) { return 0; }  // VideoToolbox decodes both
static double cb_audio_set_client_volume(void *cls) { return 0.0; }
static bool cb_check_register(void *cls, const char *pk) { return true; }
static const char *cb_passwd(void *cls, int *len) { *len = 0; return NULL; }
static void cb_noop(void *cls) {}
static void cb_noop_int(void *cls, int value) {}
static void cb_noop_buffer(void *cls, const void *buffer, int len) {}
static void cb_audio_remote_control_id(void *cls, const char *dacp_id, const char *active_remote) {}
static void cb_audio_set_progress(void *cls, uint32_t *start, uint32_t *curr, uint32_t *end) {}
static void cb_video_report_size(void *cls, float *ws, float *hs, float *w, float *h) {}
static void cb_display_pin(void *cls, char *pin) {}
static void cb_register_client(void *cls, const char *device_id, const char *pk, const char *name) {}
static void cb_export_dacp(void *cls, const char *active_remote, const char *dacp_id) {}
static void cb_on_video_play(void *cls, const char *location, const float start) {}
static void cb_on_video_float(void *cls, const float value) {}
static void cb_on_video_info(void *cls, playback_info_t *info) {}
static float cb_on_video_playlist_remove(void *cls) { return 0; }
static void cb_get_custom_profile(void *cls, const char **profile) { *profile = NULL; }

// MARK: - API

static int parse_mac(const char *mac, char out[6]) {
    unsigned int b[6];
    if (sscanf(mac, "%2x:%2x:%2x:%2x:%2x:%2x", &b[0], &b[1], &b[2], &b[3], &b[4], &b[5]) != 6) return -1;
    for (int i = 0; i < 6; i++) out[i] = (char) b[i];
    return 0;
}

int vm_airplay_start(const char *name, const char *mac, const char *keyfile,
                     int width, int height, int max_fps, vm_airplay_callbacks callbacks) {
    if (g_raop) return -1;
    g_cb = callbacks;

    char hw_addr[6];
    if (parse_mac(mac, hw_addr)) return -2;

    int error = 0;
    g_dnssd = dnssd_init(name, (int) strlen(name), hw_addr, sizeof(hw_addr), 0, &error);
    if (error || !g_dnssd) return -3;
    dnssd_set_airplay_features(g_dnssd, 0, 0);   // no HLS video
    dnssd_set_airplay_features(g_dnssd, 42, 1);  // H.265 allowed: newer iPhones send it for heights above 1080

    raop_callbacks_t cbs;
    memset(&cbs, 0, sizeof(cbs));
    cbs.video_process = cb_video_process;
    cbs.audio_process = cb_audio_process;
    cbs.audio_get_format = cb_audio_get_format;
    cbs.audio_set_volume = cb_audio_set_volume;
    cbs.report_client_request = cb_report_client_request;
    cbs.mirror_video_running = cb_mirror_video_running;
    cbs.conn_feedback = cb_conn_feedback;
    cbs.conn_reset = cb_conn_reset;
    cbs.video_reset = cb_video_reset;
    cbs.video_set_codec = cb_video_set_codec;
    cbs.audio_set_client_volume = cb_audio_set_client_volume;
    cbs.check_register = cb_check_register;
    cbs.passwd = cb_passwd;
    cbs.conn_init = cb_noop;
    cbs.conn_destroy = cb_noop;
    cbs.video_pause = cb_noop;
    cbs.video_resume = cb_noop;
    cbs.audio_flush = cb_noop;
    cbs.video_flush = cb_noop;
    cbs.audio_stop_coverart_rendering = cb_noop;
    cbs.on_video_stop = cb_noop;
    cbs.audio_set_metadata = cb_noop_buffer;
    cbs.audio_set_coverart = cb_noop_buffer;
    cbs.audio_remote_control_id = cb_audio_remote_control_id;
    cbs.audio_set_progress = cb_audio_set_progress;
    cbs.video_report_size = cb_video_report_size;
    cbs.display_pin = cb_display_pin;
    cbs.register_client = cb_register_client;
    cbs.export_dacp = cb_export_dacp;
    cbs.on_video_play = cb_on_video_play;
    cbs.on_video_scrub = cb_on_video_float;
    cbs.on_video_rate = cb_on_video_float;
    cbs.on_video_acquire_playback_info = cb_on_video_info;
    cbs.on_video_playlist_remove = cb_on_video_playlist_remove;
    cbs.get_custom_profile = cb_get_custom_profile;
    (void) cb_noop_int;

    g_raop = raop_init(&cbs);
    if (!g_raop) { vm_airplay_stop(); return -4; }
    raop_set_log_callback(g_raop, cb_log, NULL);
    raop_set_log_level(g_raop, LOGGER_INFO);
    if (raop_init2(g_raop, 1, mac, keyfile)) { free(g_raop); g_raop = NULL; vm_airplay_stop(); return -5; }

    raop_set_plist(g_raop, "width", width);
    raop_set_plist(g_raop, "height", height);
    raop_set_plist(g_raop, "refreshRate", 60);
    raop_set_plist(g_raop, "maxFPS", max_fps);

    unsigned short tcp[2] = {0, 0};
    unsigned short udp[3] = {0, 0, 0};
    raop_set_tcp_ports(g_raop, tcp);
    raop_set_udp_ports(g_raop, udp);

    unsigned short port = raop_get_port(g_raop);
    if (raop_start_httpd(g_raop, &port) < 0) { vm_airplay_stop(); return -6; }
    raop_set_port(g_raop, port);
    raop_set_dnssd(g_raop, g_dnssd);

    if (dnssd_register_raop(g_dnssd, port)) { vm_airplay_stop(); return -7; }
    if (dnssd_register_airplay(g_dnssd, port)) { vm_airplay_stop(); return -8; }
    return 0;
}

int vm_airplay_dnssd_fd(int service) {
    return g_dnssd ? dnssd_get_service_fd(g_dnssd, service) : -1;
}

int vm_airplay_dnssd_process(int service) {
    return g_dnssd ? dnssd_process_service(g_dnssd, service) : -1;
}

void vm_airplay_reset(void) {
    if (!g_raop) return;
    raop_stop_httpd(g_raop);
    raop_remove_known_connections(g_raop);
    unsigned short port = raop_get_port(g_raop);
    raop_start_httpd(g_raop, &port);
    raop_set_port(g_raop, port);
}

void vm_airplay_stop(void) {
    if (g_raop) {
        raop_destroy(g_raop);
        g_raop = NULL;
    }
    if (g_dnssd) {
        dnssd_unregister_raop(g_dnssd);
        dnssd_unregister_airplay(g_dnssd);
        dnssd_destroy(g_dnssd);
        g_dnssd = NULL;
    }
    memset(&g_cb, 0, sizeof(g_cb));
}
