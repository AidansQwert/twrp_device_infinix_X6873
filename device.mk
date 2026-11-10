# Recovery ramdisk files
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt6897.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt6897.rc \
    $(LOCAL_PATH)/recovery/root/first_stage_ramdisk/fstab.mt6897:$(TARGET_COPY_OUT_RECOVERY)/root/first_stage_ramdisk/fstab.mt6897 \
    $(LOCAL_PATH)/recovery/root/vendor/etc/init/trustonic.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/trustonic.rc \
    $(LOCAL_PATH)/recovery/root/vendor/etc/init/android.hardware.gatekeeper-service.trustonic.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/android.hardware.gatekeeper-service.trustonic.rc \
    $(LOCAL_PATH)/recovery/root/vendor/etc/init/android.hardware.security.keymint@3.0-service.trustonic.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/android.hardware.security.keymint@3.0-service.trustonic.rc
