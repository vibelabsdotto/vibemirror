#ifndef VM_AIRPLAY_H
#define VM_AIRPLAY_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Callbacks run on UxPlay's network threads. Copy data before returning.
typedef struct vm_airplay_callbacks {
    void *ctx;
    void (*client_connected)(void *ctx, const char *name, const char *model);
    void (*mirror_running)(void *ctx, bool running);
    void (*video_frame)(void *ctx, const uint8_t *annexb, int length, bool is_h265);
    void (*audio_format)(void *ctx, int compression_type, int samples_per_frame);
    void (*audio_packet)(void *ctx, const uint8_t *data, int length);
    void (*audio_volume)(void *ctx, float decibels);
    void (*heartbeat)(void *ctx);
    void (*connection_lost)(void *ctx);
    void (*log)(void *ctx, int level, const char *message);
} vm_airplay_callbacks;

/// Starts the AirPlay receiver and advertises it over Bonjour.
/// mac: "aa:bb:cc:dd:ee:ff", stable across launches so the iPhone recognises the receiver.
/// keyfile: path where the Ed25519 pairing key is stored.
/// Returns 0 on success.
int vm_airplay_start(const char *name, const char *mac, const char *keyfile,
                     int width, int height, int max_fps,
                     vm_airplay_callbacks callbacks);

/// Bonjour sockets that must be serviced when readable. service: 0 = RAOP, 1 = AirPlay.
int vm_airplay_dnssd_fd(int service);
int vm_airplay_dnssd_process(int service);

/// Drops all client connections and restarts the HTTP server on the same port.
void vm_airplay_reset(void);

void vm_airplay_stop(void);

#ifdef __cplusplus
}
#endif

#endif
