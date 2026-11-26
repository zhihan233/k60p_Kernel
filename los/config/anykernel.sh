### AnyKernel3: socrates LineageOS 23.2 base kernel (Droidspaces + BBG + game)
properties() { '
kernel.string=K60P (socrates) 5.15.211 LOS-base Droidspaces+BBG+game
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
do.check_boot_version=0
device.name1=socrates
device.name2=redmi_k60_pro
device.name3=
device.name4=
device.name5=
supported.versions=16
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=0;
. tools/ak3-core.sh;

# K60 Pro 的内核在 boot 分区（header v4，无 ramdisk），init_boot 里的
# KernelSU/SukiSU LKM 与本 ZIP 无关，不会被触碰。
split_boot;
flash_boot;
