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
 * Returns 0 if minimuxer is not ready, 1 if it is. Ready means:
 * - device connection succeeded
 * - at least 1 device exists
 * - last heartbeat was a success
 * - the developer disk image is mounted
 * # Safety
 * I don't know how you would be able to make this function unsafe to use.
 */
int minimuxer_ready(void);

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
 * Removes provisioning profiles associated with the given IDs
 * # Arguments
 * - `ids`: The bundle IDs of profiles to remove, **seperated by comma.**<br />
 *   Each profile's Name will be checked against each given ID. If the Name contains an ID, the profile will be removed.<br />
 *   Example: ids `com.SideStore.SideStore,stream.yattee.app` would remove `com.SideStore.SideStore`, `com.SideStore.SideStore.AltWidget` and `stream.yattee.app` since they all have Names that would include a given ID.
 * # Safety
 * Don't be stupid
 */
int minimuxer_remove_provisioning_profiles(char *ids);

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
