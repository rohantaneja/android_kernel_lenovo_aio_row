## AnyKernel methods (DO NOT CHANGE)
# set up extracted files and directories
ramdisk=/tmp/anykernel/ramdisk;
bin=/tmp/anykernel/tools;
split_img=/tmp/anykernel/split_img;
patch=/tmp/anykernel/patch;
legacy=/tmp/anykernel;
ramdisk_r=/tmp/anykernel/ramdisk_replace;

chmod -R 755 $bin;
mkdir -p $split_img;

FD=$1;
OUTFD=/proc/self/fd/$FD;

# ui_print <text>
ui_print() { echo -e "ui_print $1\nui_print" > $OUTFD; }

# contains <string> <substring>
contains() { test "${1#*$2}" != "$1" && return 0 || return 1; }

# file_getprop <file> <property>
file_getprop() { grep "^$2=" "$1" | cut -d= -f2; }

# reset anykernel directory
reset_ak() {
  rm -rf $(dirname /tmp/anykernel/*-files/current)/ramdisk;
  for i in $ramdisk /tmp/anykernel/rdtmp /tmp/anykernel/boot.img /tmp/anykernel/*-new*; do
    cp -af $i $(dirname /tmp/anykernel/*-files/current);
  done;
  rm -rf $ramdisk $split_img $patch /tmp/anykernel/rdtmp /tmp/anykernel/boot.img /tmp/anykernel/*-new* /tmp/anykernel/*-files/current;
  . /tmp/anykernel/tools/ak2-core.sh $FD;
}

# reset ramdisk unpack for legacy
reset_ak_legacy() {
  rm -rf $(dirname /tmp/anykernel/*-files/current)/ramdisk;
  for i in $ramdisk /tmp/anykernel/rdtmp /tmp/anykernel/*-new*; do
    cp -af $i $(dirname /tmp/anykernel/*-files/current);
  done;
  rm -rf $ramdisk /tmp/anykernel/rdtmp /tmp/anykernel/*-new* /tmp/anykernel/*-files/current;
  . /tmp/anykernel/tools/ak2-core.sh $FD;
}

# dump boot and extract ramdisk
split_boot() {
  if [ ! -e "$(echo $block | cut -d\  -f1)" ]; then
    ui_print " - Invalid partition! Aborting!"; exit 1;
  fi;
  if [ -f "$bin/nanddump" ]; then
    $bin/nanddump -f /tmp/anykernel/boot.img $block;
  else
    dd if=$block of=/tmp/anykernel/boot.img;
  fi;
  nooktest=$(strings /tmp/anykernel/boot.img | grep -E 'Red Loader|Green Loader|Green Recovery|eMMC boot.img|eMMC recovery.img|BauwksBoot');
  if [ "$nooktest" ]; then
    case $nooktest in
      *BauwksBoot*) nookoff=262144;;
      *) nookoff=1048576;;
    esac;
    mv -f /tmp/anykernel/boot.img /tmp/anykernel/boot-orig.img;
    dd bs=$nookoff count=1 conv=notrunc if=/tmp/anykernel/boot-orig.img of=$split_img/boot.img-master_boot.key;
    dd bs=$nookoff skip=1 conv=notrunc if=/tmp/anykernel/boot-orig.img of=/tmp/anykernel/boot.img;
  fi;
  if [ -f "$bin/unpackbootimg" ]; then   
    $bin/unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
  fi;
  if [ $? != 0 -o "$dumpfail" ]; then
    ui_print " - Dumping boot.img failed! Aborting!"; exit 1;
  fi;  
}
unpack_ramdisk() {
	if [ -f "$legacy/legacy" ]; then
  if [ -f "$bin/mkmtkhdr" ]; then
    dd bs=512 skip=1 conv=notrunc if=$split_img/boot.img-ramdisk.gz of=$split_img/temprd;
    mv -f $split_img/temprd $split_img/boot.img-ramdisk.gz;
  fi;
  fi;
  mv -f $ramdisk /tmp/anykernel/rdtmp;
  case $(od -ta -An -N4 $split_img/boot.img-ramdisk.gz) in
    '  us  vt'*|'  us  rs'*) compext="gz"; unpackcmd="gzip";;
    '  ht   L   Z   O') compext="lzo"; unpackcmd="lzop";;
    '   ] nul nul nul') compext="lzma"; unpackcmd="$bin/xz";;
    '   }   7   z   X') compext="xz"; unpackcmd="$bin/xz";;
    '   B   Z   h'*) compext="bz2"; unpackcmd="bzip2";;
    ' stx   !   L can') compext="lz4-l"; unpackcmd="$bin/lz4";;
    ' etx   !   L can'|' eot   "   M can') compext="lz4"; unpackcmd="$bin/lz4";;
    *) if [ -f "$legacy/legacy" ]; then abort "  - Legacy mode failed too! Aborting!"; fi; echo 1 > "$legacy/legacy"; return;;
  esac;
  mv -f $split_img/boot.img-ramdisk.gz $split_img/boot.img-ramdisk.cpio.$compext;
  mkdir -p $ramdisk;
  chmod 755 $ramdisk;
  cd $ramdisk;
  $unpackcmd -dc $split_img/boot.img-ramdisk.cpio.$compext | EXTRACT_UNSAFE_SYMLINKS=1 cpio -i -d;
  if [ $? != 0 -o -z "$(ls $ramdisk)" ]; then
    ui_print " - Unpacking ramdisk failed! Aborting!"; exit 1;
  fi;
  test ! -z "$(ls /tmp/anykernel/rdtmp)" && cp -af /tmp/anykernel/rdtmp/* $ramdisk;
  rm $ramdisk/init.spectrum.rc;
  rm $ramdisk/init.spectrum.sh; 
  cp $ramdisk_r/init.spectrum.rc $ramdisk;
  cp $ramdisk_r/init.spectrum.sh $ramdisk;
}
dump_boot() {
  split_boot;
  unpack_ramdisk;
}

# repack ramdisk then build and write image
repack_ramdisk() {
  case $ramdisk_compression in
    auto|"") compext=`echo $split_img/*-ramdisk.cpio.* | rev | cut -d. -f1 | rev`;;
    *) compext=$ramdisk_compression;;
  esac;
  case $compext in
    gz) repackcmd="gzip";;
    lzo) repackcmd="lzo";;
    lzma) repackcmd="$bin/xz -Flzma";;
    xz) repackcmd="$bin/xz -Ccrc32";;
    bz2) repackcmd="bzip2";;
    lz4-l) repackcmd="$bin/lz4 -l";;
    lz4) repackcmd="$bin/lz4";;
  esac;
  if [ -f "$bin/mkbootfs" ]; then
    $bin/mkbootfs $ramdisk | $repackcmd -9c > /tmp/anykernel/ramdisk-new.cpio.$compext;
  else
    cd $ramdisk;
    find . | cpio -H newc -o | $repackcmd -9c > /tmp/anykernel/ramdisk-new.cpio.$compext;
  fi;
  if [ $? != 0 ]; then
    ui_print " - Repacking ramdisk failed! Aborting!"; exit 1;
  fi;
  cd /tmp/anykernel;
  if [ -f "$legacy/legacy" ]; then
  if [ -f "$bin/mkmtkhdr" ]; then
    $bin/mkmtkhdr --rootfs ramdisk-new.cpio.$compext;
    mv -f ramdisk-new.cpio.$compext-mtk ramdisk-new.cpio.$compext;
  fi;
  fi;
}
flash_boot() {
  cd $split_img;
  if [ -f "$bin/mkimage" ]; then
    name=`cat *-name`;
    arch=`cat *-arch`;
    os=`cat *-os`;
    type=`cat *-type`;
    comp=`cat *-comp`;
    test "$comp" == "uncompressed" && comp=none;
    addr=`cat *-addr`;
    ep=`cat *-ep`;
  else
    if [ -f *-cmdline ]; then
      cmdline=`cat *-cmdline`;
      cmd="$split_img/boot.img-cmdline@cmdline";
    fi;
    if [ -f *-board ]; then
      board=`cat *-board`;
    fi;
    base=`cat *-base`;
    pagesize=`cat *-pagesize`;
    kerneloff=`cat *-kerneloff`;
    ramdiskoff=`cat *-ramdiskoff`;
    if [ -f *-tagsoff ]; then
      tagsoff=`cat *-tagsoff`;
    fi;
    if [ -f *-osversion ]; then
      osver=`cat *-osversion`;
    fi;
    if [ -f *-oslevel ]; then
      oslvl=`cat *-oslevel`;
    fi;
    if [ -f *-second ]; then
      second=`ls *-second`;
      second="--second $split_img/$second";
      secondoff=`cat *-secondoff`;
      secondoff="--second_offset $secondoff";
    fi;
    if [ -f *-hash ]; then
      hash=`cat *-hash`;
      test "$hash" == "unknown" && hash=sha1;
      hash="--hash $hash";
    fi;
    if [ -f *-unknown ]; then
      unknown=`cat *-unknown`;
    fi;
  fi;
  for i in zImage zImage-dtb Image.gz Image Image-dtb Image.gz-dtb Image.bz2 Image.bz2-dtb Image.lzo Image.lzo-dtb Image.lzma Image.lzma-dtb Image.xz Image.xz-dtb Image.lz4 Image.lz4-dtb Image.fit; do
    if [ -f /tmp/anykernel/$i ]; then
      kernel=/tmp/anykernel/$i;
      break;
    fi;
  done;
  if [ ! "$kernel" ]; then
    kernel=`ls *-zImage`;
    kernel=$split_img/$kernel;
  fi;
  if [ -f /tmp/anykernel/ramdisk-new.cpio.$compext ]; then
    rd=/tmp/anykernel/ramdisk-new.cpio.$compext;
  else
    rd=`ls *-ramdisk.*`;
    rd="$split_img/$rd";
  fi;
  for i in dtb dt.img; do
    if [ -f /tmp/anykernel/$i ]; then
      dtb="--dt /tmp/anykernel/$i";
      rpm="/tmp/anykernel/$i,rpm";
      break;
    fi;
  done;
  if [ ! "$dtb" -a -f *-dtb ]; then
    dtb=`ls *-dtb`;
    rpm="$split_img/$dtb,rpm";
    dtb="--dt $split_img/$dtb";
  fi;
  cd /tmp/anykernel;
  if [ -f "$legacy/legacy" ]; then
  if [ -f "$bin/mkmtkhdr" ]; then
    case $kernel in
      $split_img/*) ;;
      *) $bin/mkmtkhdr --kernel $kernel; kernel=$kernel-mtk;;
    esac;
  fi;
  fi;
  if [ -f "$bin/mkbootimg" ]; then    
    $bin/mkbootimg --kernel $kernel --ramdisk $rd $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff $secondoff --tags_offset "$tagsoff" --os_version "$osver" --os_patch_level "$oslvl" $hash $dtb --output boot-new.img;
  fi;
  if [ $? != 0 ]; then
    ui_print " - Repacking image failed! Aborting!"; exit 1;
  fi;  
  if [ "$(strings /tmp/anykernel/boot.img | grep SEANDROIDENFORCE )" ]; then
    printf 'SEANDROIDENFORCE' >> boot-new.img;
  fi;  
  if [ -f "$split_img/boot.img-master_boot.key" ]; then
    cat $split_img/boot.img-master_boot.key boot-new.img > boot-new-signed.img;
    mv -f boot-new-signed.img boot-new.img;
  fi;
  if [ ! -f /tmp/anykernel/boot-new.img ]; then
    ui_print " - Repacked image could not be found! Aborting!"; exit 1;
  elif [ "$(wc -c < boot-new.img)" -gt "$(wc -c < boot.img)" ]; then
    ui_print " - New image larger than boot partition! Aborting!"; exit 1;
  fi;
  if [ -f "$bin/flash_erase" -a -f "$bin/nandwrite" ]; then
    $bin/flash_erase $block 0 0;
    $bin/nandwrite -p $block /tmp/anykernel/boot-new.img;
  else
    dd if=/dev/zero of=$block 2>/dev/null;
    dd if=/tmp/anykernel/boot-new.img of=$block;
  fi;
  for i in dtbo dtbo.img; do
    if [ -f /tmp/anykernel/$i ]; then
      dtbo=$i;
      break;
    fi;
  done;
  if [ "$dtbo" ]; then
    dtbo_block=/dev/block/bootdevice/by-name/dtbo$slot;
    if [ ! -e "$(echo $dtbo_block)" ]; then
      ui_print " - dtbo partition could not be found! Aborting!"; exit 1;
    fi;
    if [ -f "$bin/flash_erase" -a -f "$bin/nandwrite" ]; then
      $bin/flash_erase $dtbo_block 0 0;
      $bin/nandwrite -p $dtbo_block /tmp/anykernel/$dtbo;
    else
      dd if=/dev/zero of=$dtbo_block 2>/dev/null;
      dd if=/tmp/anykernel/$dtbo of=$dtbo_block;
    fi;
  fi;
}
write_boot() {
  repack_ramdisk;
  flash_boot;
}

# backup_file <file>
backup_file() { test ! -f $1~ && cp $1 $1~; }

# restore_file <file>
restore_file() { test -f $1~ && mv -f $1~ $1; }

# replace_string <file> <if search string> <original string> <replacement string>
replace_string() {
  if [ -z "$(grep "$2" $1)" ]; then
      sed -i "s;${3};${4};" $1;
  fi;
}

# replace_section <file> <begin search string> <end search string> <replacement string>
replace_section() {
  begin=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
  if [ "$begin" ]; then
    test "$3" == " " -o -z "$3" && endstr='^$' || endstr="$3";
    for end in `grep -n "$endstr" $1 | cut -d: -f1`; do
      if [ "$end" ] && [ "$begin" -lt "$end" ]; then
        if [ "$3" == " " -o -z "$3" ]; then
          sed -i "/${2//\//\\/}/,/^\s*$/d" $1;
        else
          sed -i "/${2//\//\\/}/,/${3//\//\\/}/d" $1;
        fi;
        sed -i "${begin}s;^;${4}\n;" $1;
        break;
      fi;
    done;
  fi;
}

# remove_section <file> <begin search string> <end search string>
remove_section() {
  begin=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
  if [ "$begin" ]; then
    test "$3" == " " -o -z "$3" && endstr='^$' || endstr="$3";
    for end in `grep -n "$endstr" $1 | cut -d: -f1`; do
      if [ "$end" ] && [ "$begin" -lt "$end" ]; then
        if [ "$3" == " " -o -z "$3" ]; then
          sed -i "/${2//\//\\/}/,/^\s*$/d" $1;
        else
          sed -i "/${2//\//\\/}/,/${3//\//\\/}/d" $1;
        fi;
        break;
      fi;
    done;
  fi;
}

# insert_line <file> <if search string> <before|after> <line match string> <inserted line>
insert_line() {
  if [ -z "$(grep "$2" $1)" ]; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | head -n1 | cut -d: -f1` + offset));
    if [ -f $1 -a "$line" ] && [ "$(wc -l $1 | cut -d\  -f1)" -lt "$line" ]; then
      echo "$5" >> $1;
    else
      sed -i "${line}s;^;${5}\n;" $1;
    fi;
  fi;
}

# replace_line <file> <line replace string> <replacement line>
replace_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
    sed -i "${line}s;.*;${3};" $1;
  fi;
}

# remove_line <file> <line match string>
remove_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
    sed -i "${line}d" $1;
  fi;
}

# prepend_file <file> <if search string> <patch file>
prepend_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo "$(cat $patch/$3 $1)" > $1;
  fi;
}

# insert_file <file> <if search string> <before|after> <line match string> <patch file>
insert_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | head -n1 | cut -d: -f1` + offset));
    sed -i "${line}s;^;\n;" $1;
    sed -i "$((line - 1))r $patch/$5" $1;
  fi;
}

# append_file <file> <if search string> <patch file>
append_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo -ne "\n" >> $1;
    cat $patch/$3 >> $1;
    echo -ne "\n" >> $1;
  fi;
}

# replace_file <file> <permissions> <patch file>
replace_file() {
  cp -pf $patch/$3 $1;
  chmod $2 $1;
}

# patch_prop <prop file> <prop name> <new prop value>
patch_prop() {
  if [ -z "$(grep "^$2=" $1)" ]; then
    echo -ne "\n$2=$3\n" >> $1;
  else
    line=`grep -n "^$2=" $1 | head -n1 | cut -d: -f1`;
    sed -i "${line}s;.*;${2}=${3};" $1;
  fi;
}

# allow multi-partition ramdisk modifying configurations (using reset_ak)
if [ ! -d "$ramdisk" -a ! -d "$patch" ]; then
  if [ -d "$(basename $block)-files" ]; then
    cp -af /tmp/anykernel/$(basename $block)-files/* /tmp/anykernel;
  else
    mkdir -p /tmp/anykernel/$(basename $block)-files;
  fi;
  touch /tmp/anykernel/$(basename $block)-files/current;
fi;
test ! -d "$ramdisk" && mkdir -p $ramdisk;

## end methods

