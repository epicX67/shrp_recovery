#!/system/bin/sh
# AIK-mobile/repackimg: repack ramdisk and build image
# osm0sis @ xda-developers

case $1 in
  --help) echo "usage: repackimg.sh [--original] [--level <0-9>] [--avbkey <name>]"; return 1;
esac;

case $0 in
  *.sh) aik="$0";;
     *) aik="$(lsof -p $$ 2>/dev/null | grep -o '/.*repackimg.sh$')";;
esac;
aik="$(dirname "$(readlink -f "$aik")")";
bin="$aik/bin";
rel=bin;

abort() { cd "$aik"; echo "Error!"; }

cd "$aik";
bb=$bin/busybox;
chmod -R 755 $bin *.sh;
chmod 644 $bin/magic $bin/androidbootimg.magic $bin/BootSignature_Android.jar $bin/avb/* $bin/chromeos/*;

if [ ! -f $bb ]; then
  bb=busybox;
fi;

if [ -z "$(ls split_img/* 2>/dev/null)" -o -z "$(ls ramdisk/* 2>/dev/null)" ]; then
  echo "No files found to be packed/built.";
  abort;
  return 1;
fi;

case $0 in *.sh) clear;; esac;
echo "\nAndroid Image Kitchen - RepackImg Script";
echo "by osm0sis @ xda-developers\n";

if [ ! -z "$(ls *-new.* 2>/dev/null)" ]; then
  echo "Warning: Overwriting existing files!\n";
fi;

rm -f *-new.*;
while [ "$1" ]; do
  case $1 in
    --original) original=1;;
    --level)
      case $2 in
        ''|*[!0-9]*) ;;
        *) level="-$2"; lvltxt=" - Level: $2"; shift;;
      esac;
    ;;
    --avbkey)
      if [ "$2" ]; then
        for keytest in "$2" "$aik/$2"; do
          if [ -f "$keytest.pk8" -a -f "$keytest.x509.der" ]; then
            avbkey="$keytest"; avbtxt=" - Key: $2"; shift; break;
          fi;
        done;
      fi;
    ;;
  esac;
  shift;
done;

if [ "$original" ]; then
  echo "Repacking with original ramdisk...";
else
  echo "Packing ramdisk...\n";
  ramdiskcomp=`cat split_img/*-ramdiskcomp`;
  test ! "$level" -a "$ramdiskcomp" == "xz" && level=-1;
  echo "Using compression: $ramdiskcomp$lvltxt";
  repackcmd="$bb $ramdiskcomp $level";
  compext=$ramdiskcomp;
  case $ramdiskcomp in
    gzip) compext=gz;;
    lzop) compext=lzo;;
    xz) repackcmd="$bin/xz $level -Ccrc32";;
    lzma) repackcmd="$bin/xz $level -Flzma";;
    bzip2) compext=bz2;;
    lz4) repackcmd="$bin/lz4 $level -l";;
  esac;
  $bin/mkbootfs ramdisk | $repackcmd > ramdisk-new.cpio.$compext;
  if [ $? != "0" ]; then
    abort;
    return 1;
  fi;
fi;

echo "\nGetting build information...";
cd split_img;
kernel=`ls *-zImage`;                 echo "kernel = $kernel";
kernel="split_img/$kernel";
if [ "$original" ]; then
  ramdisk=`ls *-ramdisk.cpio*`;       echo "ramdisk = $ramdisk";
  ramdisk="split_img/$ramdisk";
else
  ramdisk="ramdisk-new.cpio.$compext";
fi;
imgtype=`cat *-imgtype`;
if [ "$imgtype" == "U-Boot" ]; then
  name=`cat *-name`;                  echo "name = $name";
  arch=`cat *-arch`;
  os=`cat *-os`;
  type=`cat *-type`;
  comp=`cat *-comp`;                  echo "type = $arch $os $type ($comp)";
  test "$comp" == "uncompressed" && comp=none;
  addr=`cat *-addr`;                  echo "load_addr = $addr";
  ep=`cat *-ep`;                      echo "entry_point = $ep";
else
  if [ -f *-second ]; then
    second=`ls *-second`;             echo "second = $second";
    second="--second split_img/$second";
  fi;
  if [ -f *-cmdline ]; then
    cmdline=`cat *-cmdline`;          echo "cmdline = $cmdline";
  fi;
  if [ -f *-board ]; then
    board=`cat *-board`;              echo "board = $board";
  fi;
  base=`cat *-base`;                  echo "base = $base";
  pagesize=`cat *-pagesize`;          echo "pagesize = $pagesize";
  kerneloff=`cat *-kerneloff`;        echo "kernel_offset = $kerneloff";
  ramdiskoff=`cat *-ramdiskoff`;      echo "ramdisk_offset = $ramdiskoff";
  if [ -f *-secondoff ]; then
    secondoff=`cat *-secondoff`;      echo "second_offset = $secondoff";
  fi;
  if [ -f *-tagsoff ]; then
    tagsoff=`cat *-tagsoff`;          echo "tags_offset = $tagsoff";
  fi;
  if [ -f *-osversion ]; then
    osver=`cat *-osversion`;          echo "os_version = $osver";
  fi;
  if [ -f *-oslevel ]; then
    oslvl=`cat *-oslevel`;            echo "os_patch_level = $oslvl";
  fi;
  if [ -f *-hash ]; then
    hash=`cat *-hash`;                echo "hash = $hash";
    hash="--hash $hash";
  fi;
  if [ -f *-dtb ]; then
    dtb=`ls *-dtb`;                   echo "dtb = $dtb";
    dtb="--dt split_img/$dtb";
  fi;
  if [ -f *-unknown ]; then
    unknown=`cat *-unknown`;          echo "unknown = $unknown";
  fi;
fi;
cd ..;

if [ -f split_img/*-mtktype ]; then
  mtktype=`cat split_img/*-mtktype`;
  echo "\nGenerating MTK headers...\n";
  echo "Using ramdisk type: $mtktype";
  $bin/mkmtkhdr --kernel "$kernel" --$mtktype "$ramdisk" >/dev/null;
  if [ $? != "0" ]; then
    abort;
    return 1;
  fi;
  mv -f $($bb basename $kernel)-mtk kernel-new.mtk;
  mv -f $($bb basename $ramdisk)-mtk $mtktype-new.mtk;
  kernel=kernel-new.mtk;
  ramdisk=$mtktype-new.mtk;
fi;

if [ -f split_img/*-sigtype ]; then
  outname=unsigned-new.img;
else
  outname=image-new.img;
fi;

if [ "$imgtype" == "ELF" ]; then
  imgtype=AOSP;
  echo "\nWarning: ELF format detected; will be repacked using AOSP format!";
fi;

echo "\nBuilding image...\n";
echo "Using format: $imgtype\n";
case $imgtype in
  AOSP) $bin/mkbootimg --kernel "$kernel" --ramdisk "$ramdisk" $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff --second_offset "$secondoff" --tags_offset "$tagsoff" --os_version "$osver" --os_patch_level "$oslvl" $hash $dtb -o $outname;;
  AOSP-PXA) $bin/pxa1088-mkbootimg --kernel "$kernel" --ramdisk "$ramdisk" $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff --second_offset "$secondoff" --tags_offset "$tagsoff" --unknown $unknown $dtb -o $outname;;
  U-Boot) $bin/mkimage -A $arch -O $os -T $type -C $comp -a $addr -e $ep -n "$name" -d "$kernel":"$ramdisk" $outname >/dev/null;;
  *) echo "\nUnsupported format."; abort; exit 1;;
esac;
if [ $? != "0" ]; then
  abort;
  return 1;
fi;

if [ -f split_img/*-sigtype ]; then
  sigtype=`cat split_img/*-sigtype`;
  if [ -f split_img/*-avbtype ]; then
    avbtype=`cat split_img/*-avbtype`;
  fi;
  if [ -f split_img/*-blobtype ]; then
    blobtype=`cat split_img/*-blobtype`;
  fi;
  echo "Signing new image...\n";
  echo "Using signature: $sigtype $avbtype$avbtxt$blobtype\n";
  test ! "$avbkey" && avbkey="$rel/avb/testkey";
  case $sigtype in
    CHROMEOS) $bin/futility vbutil_kernel --pack image-new.img --keyblock $rel/chromeos/kernel.keyblock --signprivate $rel/chromeos/kernel_data_key.vbprivk --version 1 --vmlinuz unsigned-new.img --bootloader $rel/chromeos/empty --config $rel/chromeos/empty --arch arm --flags 0x1;;
    AVB) dalvikvm -Xbootclasspath:/system/framework/core-oj.jar:/system/framework/core-libart.jar:/system/framework/conscrypt.jar:/system/framework/bouncycastle.jar -Xnodex2oat -Xnoimage-dex2oat -cp $bin/BootSignature_Android.jar com.android.verity.BootSignature /$avbtype unsigned-new.img "$avbkey.pk8" "$avbkey.x509.der" image-new.img 2>/dev/null;;
    BLOB)
      $bb printf '-SIGNED-BY-SIGNBLOB-\00\00\00\00\00\00\00\00' > image-new.img;
      $bin/blobpack tempblob $blobtype unsigned-new.img >/dev/null;
      cat tempblob >> image-new.img;
      rm -rf tempblob;
    ;;
  esac;
  if [ $? != "0" ]; then
    abort;
    exit 1;
  fi;
fi;

if [ -f split_img/*-lokitype ]; then
  lokitype=`cat split_img/*-lokitype`;
  echo "Loki patching new image...\n";
  echo "Using type: $lokitype\n";
  mv -f image-new.img unlokied-new.img;
  if [ -f aboot.img ]; then
    $bin/loki_tool patch $lokitype aboot.img unlokied-new.img image-new.img >/dev/null;
    if [ $? != "0" ]; then
      echo "Patching failed.";
      abort;
      return 1;
    fi;
  else
    echo "Device aboot.img required in script directory to find Loki patch offset.";
    abort;
    return 1;
  fi;
fi;

if [ -f split_img/*-tailtype ]; then
  tailtype=`cat split_img/*-tailtype`;
  echo "Appending footer...\n";
  echo "Using type: $tailtype\n";
  case $tailtype in
    SEAndroid) $bb printf 'SEANDROIDENFORCE' >> image-new.img;;
    Bump) $bb printf '\x41\xA9\xE4\x67\x74\x4D\x1D\x1B\xA4\x29\xF2\xEC\xEA\x65\x52\x79' >> image-new.img;;
  esac;
fi;

echo "Done!";
return 0;

