#import <CoreFoundation/CoreFoundation.h>
#import "PrivateAPI.h"

NSDictionary<NSString *, NSNumber *> * _Nonnull IOHIDReadSensorValues(
    int32_t page,
    int32_t usage,
    int64_t eventType,
    int32_t fieldBase
) {
    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (system == NULL) {
        return @{};
    }

    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(page),
        @"PrimaryUsage": @(usage),
    };
    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (services == NULL) {
        CFRelease(system);
        return @{};
    }

    NSMutableDictionary<NSString *, NSNumber *> *result = [NSMutableDictionary dictionary];
    CFIndex count = CFArrayGetCount(services);
    int32_t eventField = IOHIDEventFieldBase(fieldBase);

    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        if (service == NULL) {
            continue;
        }

        NSString *name = nil;
        CFTypeRef prop = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (prop != NULL) {
            if (CFGetTypeID(prop) == CFStringGetTypeID()) {
                name = [(__bridge NSString *)prop copy];
            }
            CFRelease(prop);
        }

        if (name.length == 0 || result[name] != nil) {
            continue;
        }

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, eventType, 0, 0);
        if (event != NULL) {
            double value = IOHIDEventGetFloatValue(event, eventField);
            result[name] = @(value);
            CFRelease(event);
        }
    }

    CFRelease(services);
    CFRelease(system);
    return [result copy];
}
