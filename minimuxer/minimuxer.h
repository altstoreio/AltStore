// Jackson Coxson

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>


/**
 * Mount iOS's developer DMG
 * # Safety
 * Don't be stupid
 */
void minimuxer_auto_mount(char *docs_path);

/**
 * Starts the muxer and heartbeat client
 * # Arguments
 * Pairing file as a list of chars and the length
 * # Safety
 * Don't be stupid
 */
int minimuxer_c_start(char *pairing_file, char *log_path);

/**
 * Debugs an app from an app ID
 * # Safety
 * Don't be stupid
 */
int minimuxer_debug_app(char *app_id);

/**
 * Installs an ipa with a bundle ID
 * Expects the ipa to be in the afc jail from yeet_app_afc
 * # Safety
 * Don't be stupid
 */
int minimuxer_install_ipa(char *bundle_id);

/**
 * Installs a provisioning profile on the device
 * # Arguments
 * Pass a pointer to a plist
 * # Returns
 * 0 on success
 * # Safety
 * Don't be stupid
 */
int minimuxer_install_provisioning_profile(uint8_t *pointer, unsigned int len);

/**
 * Removes an app from the device
 * # Safety
 * Don't be stupid
 */
int minimuxer_remove_app(char *bundle_id);

/**
 * Removes a provisioning profile
 * # Safety
 * Don't be stupid
 */
int minimuxer_remove_provisioning_profile(char *id);

/**
 * Yeets an ipa to the afc jail
 * # Safety
 * Don't be stupid
 */
int minimuxer_yeet_app_afc(char *bundle_id, uint8_t *bytes_ptr, unsigned long bytes_len);

/**
 * Sets the current environment variable for libusbmuxd to localhost
 */
void target_minimuxer_address(void);
