# Binding generator report

Written by `tools/bindgen/gen.py`. It lists what was generated and, more importantly,
what was **not** bound and why.

- Files: 123
- Functions bound: 1649
- Through the float bridge (`lib/sce/bridge.c`): 21

## Generated files

| File | Headers | Functions | Stub libraries |
|---|---|---|---|
| `appmgr.odin` | psp2/appmgr.h | 41 | -lSceAppMgr_stub |
| `apputil.odin` | psp2/apputil.h | 24 | -lSceAppUtil_stub |
| `atrac.odin` | psp2/atrac.h | 24 | -lSceAtrac_stub |
| `audiodec.odin` | psp2/audiodec.h | 12 | -lSceAudiodec_stub |
| `audioenc.odin` | psp2/audioenc.h | 8 | -lSceAudioenc_stub |
| `audioin.odin` | psp2/audioin.h | 5 | -lSceAudioIn_stub |
| `audioout.odin` | psp2/audioout.h | 9 | -lSceAudio_stub |
| `avconfig.odin` | psp2/avconfig.h | 7 | -lSceAVConfig_stub |
| `avplayer.odin` | psp2/avplayer.h | 15 | -lSceAvPlayer_stub |
| `bgapputil.odin` | psp2/bgapputil.h | 1 | -lSceBgAppUtil_stub |
| `camera.odin` | psp2/camera.h | 45 | -lSceCamera_stub |
| `common_dialog.odin` | psp2/common_dialog.h | 2 | -lSceCommonDialog_stub |
| `compat.odin` | psp2/compat.h | 30 | -lSceCompat_stub |
| `ctrl.odin` | psp2/ctrl.h, psp2common/ctrl.h | 24 | -lSceCtrl_stub |
| `deci4p_user.odin` | psp2/deci4p/user.h | 8 | -lSceDeci4pUserp_stub |
| `defs.odin` | psp2common/defs.h | 0 |  |
| `display.odin` | psp2/display.h, psp2common/display.h | 17 | -lSceDisplay_stub |
| `dmac5.odin` | psp2/dmac5.h | 2 | -lSceSblSsMgr_stub |
| `error.odin` | psp2/error.h | 1 | -lSceError_stub |
| `fiber.odin` | psp2/fiber.h | 8 | -lSceFiber_stub |
| `fios2.odin` | psp2common/fios2.h | 0 |  |
| `fios2kernel.odin` | psp2/fios2kernel.h | 20 | -lSceFios2Kernel_stub |
| `fios2kernel02.odin` | psp2/fios2kernel02.h | 1 | -lSceFios2Kernel_stub |
| `gps.odin` | psp2/gps.h | 11 | -lSceGps_stub |
| `gxm.odin` | psp2/gxm.h | 225 | -lSceGxm_stub |
| `gxt.odin` | psp2/gxt.h | 0 |  |
| `hid.odin` | psp2/hid.h | 5 | -lSceHid_stub |
| `ime_dialog.odin` | psp2/ime_dialog.h | 5 | -lSceCommonDialog_stub |
| `incoming_dialog.odin` | psp2/incoming_dialog.h | 6 | -lSceIncomingDialog_stub |
| `io_devctl.odin` | psp2/io/devctl.h | 3 | -lSceLibKernel_stub |
| `io_dirent.odin` | psp2/io/dirent.h | 3 | -lSceIofilemgr_stub -lSceLibKernel_stub |
| `io_fcntl.odin` | psp2/io/fcntl.h | 19 | -lSceIofilemgr_stub -lSceLibKernel_stub |
| `io_stat.odin` | psp2/io/stat.h | 6 | -lSceLibKernel_stub |
| `jpeg.odin` | psp2/jpeg.h | 6 | -lSceJpeg_stub |
| `jpegarm.odin` | psp2/jpegarm.h | 3 | -lSceJpegArm_stub |
| `jpegenc.odin` | psp2/jpegenc.h, psp2common/jpegenc.h | 10 | -lSceJpegEnc_stub |
| `jpegencarm.odin` | psp2/jpegencarm.h | 8 | -lSceJpegEncArm_stub |
| `kernel_clib.odin` | psp2/kernel/clib.h | 36 | -lSceLibKernel_stub |
| `kernel_cpu.odin` | psp2/kernel/cpu.h | 73 | -lSceLibKernel_stub -lSceSysmem_stub |
| `kernel_dmac.odin` | psp2/kernel/dmac.h | 2 | -lSceKernelDmacMgr_stub |
| `kernel_error.odin` | psp2/kernel/error.h | 0 |  |
| `kernel_iofilemgr.odin` | psp2common/kernel/iofilemgr.h | 0 |  |
| `kernel_modulemgr.odin` | psp2/kernel/modulemgr.h, psp2common/kernel/modulemgr.h | 20 | -lSceKernelModulemgr_stub -lSceLibKernel_stub |
| `kernel_msif.odin` | psp2common/kernel/msif.h | 0 |  |
| `kernel_openpsid.odin` | psp2/kernel/openpsid.h | 1 | -lSceLibKernel_stub |
| `kernel_processmgr.odin` | psp2/kernel/processmgr.h, psp2common/kernel/processmgr.h | 16 | -lSceLibKernel_stub -lSceProcessmgr_stub |
| `kernel_rng.odin` | psp2/kernel/rng.h | 1 | -lSceLibKernel_stub |
| `kernel_rtc.odin` | psp2common/kernel/rtc.h | 0 |  |
| `kernel_sysmem.odin` | psp2/kernel/sysmem.h, psp2common/kernel/sysmem.h | 16 | -lSceSysmem_stub |
| `kernel_threadmgr.odin` | psp2common/kernel/threadmgr.h | 0 |  |
| `kernel_threadmgr_callback.odin` | psp2/kernel/threadmgr/callback.h | 7 | -lSceKernelThreadMgr_stub -lSceLibKernel_stub |
| `kernel_threadmgr_cond.odin` | psp2/kernel/threadmgr/cond.h | 9 | -lSceKernelThreadMgr_stub -lSceLibKernel_stub |
| `kernel_threadmgr_eventflag.odin` | psp2/kernel/threadmgr/eventflag.h | 8 | -lSceKernelThreadMgr_stub -lSceLibKernel_stub |
| `kernel_threadmgr_lw_cond.odin` | psp2/kernel/threadmgr/lw_cond.h | 6 | -lSceLibKernel_stub |
| `kernel_threadmgr_lw_mutex.odin` | psp2/kernel/threadmgr/lw_mutex.h | 5 | -lSceLibKernel_stub |
| `kernel_threadmgr_msgpipe.odin` | psp2/kernel/threadmgr/msgpipe.h | 10 | -lSceKernelThreadMgr_stub -lSceLibKernel_stub |
| `kernel_threadmgr_mutex.odin` | psp2/kernel/threadmgr/mutex.h | 10 | -lSceKernelThreadMgr_stub -lSceLibKernel_stub |
| `kernel_threadmgr_rwlock.odin` | psp2/kernel/threadmgr/rwlock.h | 13 | -lSceKernelThreadMgr_stub -lSceLibKernel_stub |
| `kernel_threadmgr_semaphore.odin` | psp2/kernel/threadmgr/semaphore.h | 10 | -lSceKernelThreadMgr_stub -lSceLibKernel_stub |
| `kernel_threadmgr_signal.odin` | psp2/kernel/threadmgr/signal.h | 2 | -lSceKernelThreadMgr_stub -lSceLibKernel_stub |
| `kernel_threadmgr_thread.odin` | psp2/kernel/threadmgr/thread.h | 28 | -lSceKernelThreadMgr_stub -lSceLibKernel_stub |
| `kernel_threadmgr_vfp.odin` | psp2/kernel/threadmgr/vfp.h | 1 | -lSceKernelThreadMgr_stub |
| `libdbg.odin` | psp2/libdbg.h | 5 | -lSceLibDbg_stub |
| `libime.odin` | psp2/libime.h | 6 | -lSceIme_stub |
| `libssl.odin` | psp2/libssl.h | 11 | -lSceSsl_stub |
| `location.odin` | psp2/location.h | 17 | -lSceLocation_stub |
| `message_dialog.odin` | psp2/message_dialog.h | 9 | -lSceCommonDialog_stub |
| `motion.odin` | psp2/motion.h | 19 | -lSceMotion_stub |
| `motion_dev.odin` | psp2/motion_dev.h | 27 | -lSceMotionDev_stub |
| `mp4rec.odin` | psp2/mp4rec.h | 8 | -lSceLibMp4Recorder_stub |
| `mtpif.odin` | psp2/mtpif.h | 2 | -lSceMtpIfDriver_stub |
| `musicexport.odin` | psp2/musicexport.h | 1 | -lSceMusicExport_stub |
| `net.odin` | psp2common/net.h | 0 |  |
| `net_adhoc_matching.odin` | psp2/net/adhoc_matching.h | 14 | -lSceNetAdhocMatching_stub |
| `net_http.odin` | psp2/net/http.h | 54 | -lSceHttp_stub |
| `net_net.odin` | psp2/net/net.h | 58 | -lSceNet_stub |
| `net_net_syscalls.odin` | psp2/net/net_syscalls.h | 34 | -lSceNetPs_stub |
| `net_netctl.odin` | psp2/net/netctl.h | 16 | -lSceNetCtl_stub |
| `netcheck_dialog.odin` | psp2/netcheck_dialog.h | 6 | -lSceCommonDialog_stub |
| `ngs_internal.odin` | psp2/ngs_internal.h | 60 | -lSceNgs_stub |
| `notificationutil.odin` | psp2/notificationutil.h | 6 | -lSceNotificationUtil_stub |
| `np_common.odin` | psp2/np/common.h | 0 |  |
| `np_mgr.odin` | psp2/np/mgr.h | 4 | -lSceNpManager_stub |
| `npdrm.odin` | psp2/npdrm.h, psp2common/npdrm.h | 5 | -lSceNpDrm_stub |
| `npdrmpackage.odin` | psp2/npdrmpackage.h | 2 | -lSceNpDrm_stub |
| `pamgr.odin` | psp2/pamgr.h | 27 | -lScePamgr_stub |
| `perf.odin` | psp2/perf.h | 9 | -lScePerf_stub |
| `pgf.odin` | psp2/pgf.h | 23 | -lScePgf_stub |
| `photo_import_dialog.odin` | psp2/photo_import_dialog.h | 5 | -lSceCommonDialog_stub |
| `photo_review_dialog.odin` | psp2/photo_review_dialog.h | 5 | -lSceCommonDialog_stub |
| `photoexport.odin` | psp2/photoexport.h | 2 | -lScePhotoExport_stub |
| `power.odin` | psp2/power.h, psp2common/power.h | 30 | -lScePower_stub |
| `promoterutil.odin` | psp2/promoterutil.h | 10 | -lScePromoterUtil_stub |
| `pspnet_adhoc.odin` | psp2/pspnet_adhoc.h | 19 | -lScePspnetAdhoc_stub |
| `pspnet_adhocctl.odin` | psp2/pspnet_adhocctl.h | 9 | -lScePspnetAdhoc_stub |
| `pss.odin` | psp2/pss.h | 7 | -lSceLibMonoBridge_stub |
| `pvf.odin` | psp2/pvf.h | 33 | -lScePvf_stub |
| `razor_capture.odin` | psp2/razor_capture.h | 2 | -lSceRazorCapture_stub |
| `razor_hud.odin` | psp2/razor_hud.h | 4 | -lSceRazorHud_stub |
| `registrymgr.odin` | psp2/registrymgr.h | 12 | -lSceRegistryMgr_stub |
| `rtc.odin` | psp2/rtc.h | 50 | -lSceRtc_stub |
| `sblacmgr.odin` | psp2/sblacmgr.h | 1 | -lSceLibKernel_stub |
| `screenshot.odin` | psp2/screenshot.h | 4 | -lSceScreenShot_stub |
| `shacccg.odin` | psp2/shacccg.h | 7 | -lSceShaccCg_stub |
| `sharedfb.odin` | psp2/sharedfb.h | 5 | -lSceAppMgr_stub |
| `shellutil.odin` | psp2/shellutil.h | 6 | -lSceShellSvc_stub |
| `shutter_sound.odin` | psp2/shutter_sound.h | 1 | -lSceShutterSound_stub |
| `sqlite.odin` | psp2/sqlite.h | 1 | -lSceSqlite_stub |
| `sysmodule.odin` | psp2/sysmodule.h | 8 | -lSceSysmodule_stub |
| `system_param.odin` | psp2/system_param.h | 0 |  |
| `touch.odin` | psp2/touch.h | 7 | -lSceTouch_stub |
| `triggerutil.odin` | psp2/triggerutil.h | 11 | -lSceTriggerUtil_stub |
| `types.odin` | psp2common/types.h | 0 |  |
| `udcd.odin` | psp2/udcd.h, psp2common/udcd.h | 6 | -lSceUdcd_stub |
| `update.odin` | psp2/update.h | 3 | -lSceSblUpdateMgr_stub |
| `usbaudioin.odin` | psp2/usbaudioin.h | 8 | -lSceUsbAudioIn_stub |
| `usbd.odin` | psp2/usbd.h, psp2common/usbd.h | 23 | -lSceUsbd_stub |
| `usbserial.odin` | psp2/usbserial.h | 7 | -lSceUsbSerial_stub |
| `usbserv.odin` | psp2/usbserv.h, psp2common/usbserv.h | 2 | -lSceUsbServ_stub |
| `usbstorvstor.odin` | psp2/usbstorvstor.h | 4 | -lSceUsbstorVStorDriver_stub |
| `videodec.odin` | psp2/videodec.h | 6 | -lSceVideodec_stub |
| `videoexport.odin` | psp2/videoexport.h | 1 | -lSceVideoExport_stub |
| `vshbridge.odin` | psp2/vshbridge.h | 39 | -lSceVshBridge_stub |

## Float-bridged functions

- `sceGxmSetViewport` (psp2/gxm.h, SceGxm_stub)
- `sceGxmSetWClampValue` (psp2/gxm.h, SceGxm_stub)
- `sceGxmDepthStencilSurfaceGetBackgroundDepth` (psp2/gxm.h, SceGxm_stub)
- `sceGxmDepthStencilSurfaceSetBackgroundDepth` (psp2/gxm.h, SceGxm_stub)
- `sceMotionRotateYaw` (psp2/motion.h, SceMotion_stub)
- `sceMotionSetAngleThreshold` (psp2/motion.h, SceMotion_stub)
- `sceMotionGetAngleThreshold` (psp2/motion.h, SceMotion_stub)
- `sceFontSetResolution` (psp2/pgf.h, ScePgf_stub)
- `sceFontPixelToPointH` (psp2/pgf.h, ScePgf_stub)
- `sceFontPixelToPointV` (psp2/pgf.h, ScePgf_stub)
- `sceFontPointToPixelH` (psp2/pgf.h, ScePgf_stub)
- `sceFontPointToPixelV` (psp2/pgf.h, ScePgf_stub)
- `scePvfSetEM` (psp2/pvf.h, ScePvf_stub)
- `scePvfSetResolution` (psp2/pvf.h, ScePvf_stub)
- `scePvfSetCharSize` (psp2/pvf.h, ScePvf_stub)
- `scePvfSetEmboldenRate` (psp2/pvf.h, ScePvf_stub)
- `scePvfSetSkewValue` (psp2/pvf.h, ScePvf_stub)
- `scePvfPixelToPointH` (psp2/pvf.h, ScePvf_stub)
- `scePvfPixelToPointV` (psp2/pvf.h, ScePvf_stub)
- `scePvfPointToPixelH` (psp2/pvf.h, ScePvf_stub)
- `scePvfPointToPixelV` (psp2/pvf.h, ScePvf_stub)

## Headers skipped

- `psp2/paf.h`: umbrella include only
- `psp2/paf/graphics.h`: ScePaf, system-app only
- `psp2/paf/misc.h`: ScePaf, system-app only
- `psp2/paf/stdc.h`: ScePaf copies of libc (sce_paf_private_*); system-app only

## Functions declared in a header but exported by no user-mode stub library (not bound)


## Functions that pass or return a struct by value (not bound; need a hand-written bridge)


## `static inline` functions in headers (no symbol to bind; ported by hand in lib/sce/inline.odin)

- `_sceCommonDialogSetMagicNumber` (psp2/common_dialog.h)
- `sceCommonDialogConfigParamInit` (psp2/common_dialog.h)
- `sceRtcGetYear` (psp2/rtc.h)
- `sceRtcGetMonth` (psp2/rtc.h)
- `sceRtcGetDay` (psp2/rtc.h)
- `sceRtcGetHour` (psp2/rtc.h)
- `sceRtcGetMinute` (psp2/rtc.h)
- `sceRtcGetSecond` (psp2/rtc.h)
- `sceRtcGetMicrosecond` (psp2/rtc.h)
- `sceRtcSetYear` (psp2/rtc.h)
- `sceRtcSetMonth` (psp2/rtc.h)
- `sceRtcSetDay` (psp2/rtc.h)
- `sceRtcSetHour` (psp2/rtc.h)
- `sceRtcSetMinute` (psp2/rtc.h)
- `sceRtcSetSecond` (psp2/rtc.h)
- `sceRtcSetMicrosecond` (psp2/rtc.h)
- `sceSblDmac5AesCbcEnc` (psp2/dmac5.h)
- `sceSblDmac5AesCbcDec` (psp2/dmac5.h)
- `sceSblDmac5AesCtrEnc` (psp2/dmac5.h)
- `sceSblDmac5AesCtrDec` (psp2/dmac5.h)
- `sceSblDmac5Sha256Digest` (psp2/dmac5.h)
- `sceGxtGetDataAddress` (psp2/gxt.h)
- `sceImeParamInit` (psp2/libime.h)
- `sceImeDialogParamInit` (psp2/ime_dialog.h)
- `sceIncomingDialogParamInit` (psp2/incoming_dialog.h)
- `sceMsgDialogParamInit` (psp2/message_dialog.h)
- `sceNetCheckDialogParamInit` (psp2/netcheck_dialog.h)
- `scePhotoImportDialogParamInit` (psp2/photo_import_dialog.h)
- `scePhotoReviewDialogParamInit` (psp2/photo_review_dialog.h)
- `sceSharedFbOpen` (psp2/sharedfb.h)

## Function-like macros (the useful ones are ported by hand in lib/sce/inline.odin)

- `SCE_ALIGN` (psp2common/types.h)
- `SCE_DEPRECATED` (psp2common/types.h)
- `SCE_DEPRECATED_EX` (psp2common/types.h)
- `SCE_S_ISLNK` (psp2common/kernel/iofilemgr.h)
- `SCE_S_ISREG` (psp2common/kernel/iofilemgr.h)
- `SCE_S_ISDIR` (psp2common/kernel/iofilemgr.h)
- `SCE_SO_ISLNK` (psp2common/kernel/iofilemgr.h)
- `SCE_SO_ISREG` (psp2common/kernel/iofilemgr.h)
- `SCE_SO_ISDIR` (psp2common/kernel/iofilemgr.h)
- `SCE_AUDIODEC_ROUND_UP` (psp2/audiodec.h)
- `SCE_ATRAC_ROUND_UP` (psp2/atrac.h)
- `sceRtcGetCurrentTickUtc` (psp2/rtc.h)
- `sceRtcGetCurrentClockUtc` (psp2/rtc.h)
- `sceRtcGetCurrentNetworkTickUtc` (psp2/rtc.h)
- `sceRtcConvertTime_tToDateTime` (psp2/rtc.h)
- `sceRtcConvertTime64_tToDateTime` (psp2/rtc.h)
- `sceRtcConvertDateTimeToTime_t` (psp2/rtc.h)
- `sceRtcConvertDateTimeToTime64_t` (psp2/rtc.h)
- `sceRtcConvertDosTimeToDateTime` (psp2/rtc.h)
- `sceRtcConvertDateTimeToDosTime` (psp2/rtc.h)
- `sceRtcConvertWin32TimeToDateTime` (psp2/rtc.h)
- `sceRtcConvertDateTimeToWin32Time` (psp2/rtc.h)
- `sceRtcConvertTickToDateTime` (psp2/rtc.h)
- `sceRtcConvertDateTimeToTick` (psp2/rtc.h)
- `SCE_DBG_ASSERT` (psp2/libdbg.h)
- `SCE_DBG_ASSERT_MSG` (psp2/libdbg.h)
- `SCE_DBG_LOG` (psp2/libdbg.h)
- `SCE_DBG_LOG_TRACE` (psp2/libdbg.h)
- `SCE_DBG_LOG_INFO` (psp2/libdbg.h)
- `SCE_DBG_LOG_DEBUG` (psp2/libdbg.h)
- `SCE_DBG_LOG_WARNING` (psp2/libdbg.h)
- `SCE_DBG_LOG_ERROR` (psp2/libdbg.h)
- `sceSslEnd` (psp2/libssl.h)

## Object-like macros that were not translated

- `SCE_DBG_COMPONENT`: `NULL`
- `SCE_DBG_BREAK_ACTION`: `asm volatile ("bkpt 0x0")`

## Notes

