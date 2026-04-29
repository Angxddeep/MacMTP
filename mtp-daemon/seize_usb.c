// IOKit helper to seize a USB device from the macOS kernel driver.
// The AppleUSBPTP kernel driver holds MTP/PTP devices exclusively.
// This uses USBDeviceOpenSeize() to forcibly take the device, then releases it
// so that nusb/mtp-rs can open it cleanly.

#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/usb/USBSpec.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdint.h>

// Seize and release a USB device by vendor/product/serial.
// Returns 0 on success, non-zero on error.
int seize_usb_device(uint16_t vendor_id, uint16_t product_id, const char *serial) {
    kern_return_t kr;
    io_iterator_t iterator = IO_OBJECT_NULL;
    io_service_t usb_device = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = NULL;
    CFNumberRef vid_num = NULL, pid_num = NULL;
    int found = 0;
    int result = -1;

    // Build matching dictionary
    matching = IOServiceMatching("IOUSBDevice");
    if (!matching) {
        fprintf(stderr, "seize: IOServiceMatching failed\n");
        return -1;
    }

    vid_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt16Type, &vendor_id);
    pid_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt16Type, &product_id);
    CFDictionarySetValue(matching, CFSTR(kUSBVendorID), vid_num);
    CFDictionarySetValue(matching, CFSTR(kUSBProductID), pid_num);

    kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    matching = NULL; // IOServiceGetMatchingServices consumes the dictionary

    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "seize: IOServiceGetMatchingServices failed: 0x%x\n", kr);
        goto cleanup;
    }

    while ((usb_device = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        // Check serial number if provided
        if (serial) {
            CFStringRef serial_ref = IORegistryEntrySearchCFProperty(
                usb_device, kIOServicePlane, CFSTR(kUSBSerialNumberString),
                kCFAllocatorDefault, kIORegistryIterateRecursively);
            if (serial_ref) {
                char serial_buf[256];
                if (CFStringGetCString(serial_ref, serial_buf, sizeof(serial_buf), kCFStringEncodingUTF8)) {
                    if (strcmp(serial_buf, serial) != 0) {
                        CFRelease(serial_ref);
                        IOObjectRelease(usb_device);
                        continue;
                    }
                }
                CFRelease(serial_ref);
            }
        }

        // Found the device. Get the plugin interface.
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        kr = IOCreatePlugInInterfaceForService(
            usb_device,
            kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &plugin,
            &score);

        if (kr != KERN_SUCCESS || !plugin) {
            fprintf(stderr, "seize: IOCreatePlugInInterfaceForService failed: 0x%x\n", kr);
            IOObjectRelease(usb_device);
            continue;
        }

        IOUSBDeviceInterface **dev = NULL;
        HRESULT hr = (*plugin)->QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
            (LPVOID *)&dev);

        if (hr != S_OK || !dev) {
            fprintf(stderr, "seize: QueryInterface failed: 0x%lx\n", (long)hr);
            IODestroyPlugInInterface(plugin);
            IOObjectRelease(usb_device);
            continue;
        }

        // Try to seize the device
        kr = (*dev)->USBDeviceOpenSeize(dev);
        if (kr == KERN_SUCCESS) {
            fprintf(stderr, "seize: successfully seized device, releasing...\n");
            // Release immediately so nusb can open it
            (*dev)->USBDeviceClose(dev);
            result = 0;
            found = 1;
        } else {
            fprintf(stderr, "seize: USBDeviceOpenSeize failed: 0x%x\n", kr);
        }

        (*dev)->Release(dev);
        IODestroyPlugInInterface(plugin);
        IOObjectRelease(usb_device);

        if (found) break;
    }

cleanup:
    if (vid_num) CFRelease(vid_num);
    if (pid_num) CFRelease(pid_num);
    if (iterator != IO_OBJECT_NULL) IOObjectRelease(iterator);
    return result;
}
