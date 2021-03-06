#!/bin/sh

set -e

cd $(dirname $0)
. ./machine.conf

echo "Demo Installer: platform: $platform"

# Install demo on same block device as ONIE
blk_dev=$(blkid | grep ONIE-BOOT | awk '{print $1}' | sed -e 's/[0-9]://' | head -n 1)

[ -b "$blk_dev" ] || {
    echo "Error: Unable to determine block device of ONIE install"
    exit 1
}

# The build system prepares this script by replacing %%DEMO-TYPE%%
# with "OS" or "DIAG".
demo_type="%%DEMO_TYPE%%"

demo_volume_label="ONIE-DEMO-${demo_type}"

# determine ONIE partition type
onie_partition_type=$(onie-sysinfo -t)
# demo partition size in MB
demo_part_size=128
if [ "$onie_partition_type" = "gpt" ] ; then
    create_demo_partition="create_demo_gpt_partition"
    grub_part_type="gpt"
elif [ "$onie_partition_type" = "msdos" ] ; then
    create_demo_partition="create_demo_msdos_partition"
    grub_part_type="msdos"
else
    echo "ERROR: Unsupported partition type: $onie_partition_type"
    exit 1
fi

# Creates a new partition for the DEMO OS.
# 
# arg $1 -- base block device
#
# Returns the created partition number in $demo_part
demo_part=
create_demo_gpt_partition()
{
    blk_dev="$1"

    # See if demo partition already exists
    demo_part=$(sgdisk -p $blk_dev | grep "$demo_volume_label" | awk '{print $1}')
    if [ -n "$demo_part" ] ; then
        # delete existing partition
        sgdisk -d $demo_part $blk_dev || {
            echo "Error: Unable to delete partition $demo_part on $blk_dev"
            exit 1
        }
        partprobe
    fi

    # Find next available partition
    last_part=$(sgdisk -p $blk_dev | tail -n 1 | awk '{print $1}')
    demo_part=$(( $last_part + 1 ))

    # Create new partition
    echo "Creating new demo partition ${blk_dev}$demo_part ..."

    if [ "$demo_type" = "DIAG" ] ; then
        # set the GPT 'system partition' attribute bit for the DIAG
        # partition.
        attr_bitmask="0x1"
    else
        attr_bitmask="0x0"
    fi
    sgdisk --new=${demo_part}::+${demo_part_size}MB \
        --attributes=${demo_part}:=:$attr_bitmask \
        --change-name=${demo_part}:$demo_volume_label $blk_dev || {
        echo "Error: Unable to create partition $demo_part on $blk_dev"
        exit 1
    }
    partprobe
}

create_demo_msdos_partition()
{
    blk_dev="$1"

    # See if demo partition already exists -- look for the filesystem
    # label.
    part_info="$(blkid | grep $demo_volume_label | awk -F: '{print $1}')"
    if [ -n "$part_info" ] ; then
        # delete existing partition
        demo_part="$(echo -n $part_info | sed -e s#${blk_dev}##)"
        parted -s $blk_dev rm $demo_part || {
            echo "Error: Unable to delete partition $demo_part on $blk_dev"
            exit 1
        }
        partprobe
    fi

    # Find next available partition
    last_part_info="$(parted -s -m $blk_dev unit s print | tail -n 1)"
    last_part_num="$(echo -n $last_part_info | awk -F: '{print $1}')"
    last_part_end="$(echo -n $last_part_info | awk -F: '{print $3}')"
    # Remove trailing 's'
    last_part_end=${last_part_end%s}
    demo_part=$(( $last_part_num + 1 ))
    demo_part_start=$(( $last_part_end + 1 ))
    # sectors_per_mb = (1024 * 1024) / 512 = 2048
    sectors_per_mb=2048
    demo_part_end=$(( $demo_part_start + ( $demo_part_size * $sectors_per_mb ) - 1 ))

    # Create new partition
    echo "Creating new demo partition ${blk_dev}$demo_part ..."
    parted -s --align optimal $blk_dev unit s \
      mkpart primary $demo_part_start $demo_part_end set $demo_part boot on || {
        echo "ERROR: Problems creating demo msdos partition $demo_part on: $blk_dev"
        exit 1
    }
    partprobe

}

eval $create_demo_partition $blk_dev
demo_dev="${blk_dev}$demo_part"
partprobe

# Create filesystem on demo partition with a label
mkfs.ext4 -L $demo_volume_label $demo_dev || {
    echo "Error: Unable to create file system on $demo_dev"
    exit 1
}

# Mount demo filesystem
demo_mnt="/boot"

mkdir -p $demo_mnt || {
    echo "Error: Unable to create demo file system mount point: $demo_mnt"
    exit 1
}
mount -t ext4 -o defaults,rw $demo_dev $demo_mnt || {
    echo "Error: Unable to mount $demo_dev on $demo_mnt"
    exit 1
}

# Copy kernel and initramfs to demo file system
cp demo.vmlinuz demo.initrd $demo_mnt

# store installation log in demo file system
onie-support $demo_mnt

# Pretend we are a major distro and install GRUB into the MBR of
# $blk_dev.
grub-install --boot-directory="$demo_mnt" --recheck "$blk_dev" || {
    echo "ERROR: grub-install failed on: $blk_dev"
    exit 1
}

if [ "$demo_type" = "DIAG" ] ; then
    # Install GRUB in the partition also.  This allows for
    # chainloading the DIAG image from another OS.
    #
    # We are installing GRUB in a partition, as opposed to the
    # MBR.  With this method block lists are used to refer to the
    # the core.img file.  The sector locations of core.img may
    # change whenever the file system in the partition is being
    # altered (files copied, deleted etc.). For more info, see
    # https://bugzilla.redhat.com/show_bug.cgi?id=728742 and
    # https://bugzilla.redhat.com/show_bug.cgi?id=730915.
    #
    # The workaround for this is to set the immutable flag on
    # /boot/grub/i386-pc/core.img using the chattr command so that
    # the sector locations of the core.img file in the disk is not
    # altered. The immutable flag on /boot/grub/i386-pc/core.img
    # needs to be set only if GRUB is installed to a partition
    # boot sector or a partitionless disk, not in case of
    # installation to MBR.

    core_img="$demo_mnt/grub/i386-pc/core.img"
    # remove immutable flag if file exists during the update.
    [ -f "$core_img" ] && chattr -i $core_img

    grub_install_log=$(mktemp)
    grub-install --force --boot-directory="$demo_mnt" \
        --recheck "$demo_dev" > /$grub_install_log 2>&1 || {
        echo "ERROR: grub-install failed on: $demo_dev"
        cat $grub_install_log && rm -f $grub_install_log
        exit 1
    }
    rm -f $grub_install_log

    # restore immutable flag on the core.img file as discussed
    # above.
    [ -f "$core_img" ] && chattr +i $core_img

fi

# Create a minimal grub.cfg that allows for:
#   - configure the serial console
#   - allows for grub-reboot to work
#   - a menu entry for the DEMO OS
#   - menu entries for ONIE

grub_cfg=$(mktemp)

# Set a few GRUB_xxx environment variables that will be picked up and
# used by the 50_onie_grub script.  This is similiar to what an OS
# would specify in /etc/default/grub.
#
# GRUB_SERIAL_COMMAND
# GRUB_CMDLINE_LINUX

[ -r ./platform.conf ] && . ./platform.conf

DEFAULT_GRUB_SERIAL_COMMAND="serial --port=0x3f8 --speed=115200 --word=8 --parity=no --stop=1"
DEFAULT_GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200n8"
GRUB_SERIAL_COMMAND=${GRUB_SERIAL_COMMAND:-"$DEFAULT_GRUB_SERIAL_COMMAND"}
GRUB_CMDLINE_LINUX=${GRUB_CMDLINE_LINUX:-"$DEFAULT_GRUB_CMDLINE_LINUX"}
export GRUB_SERIAL_COMMAND
export GRUB_CMDLINE_LINUX

# Add common configuration, like the timeout and serial console.
(cat <<EOF
$GRUB_SERIAL_COMMAND
terminal_input serial
terminal_output serial

set timeout=5

EOF
) > $grub_cfg

# Add the logic to support grub-reboot
(cat <<EOF
if [ -s \$prefix/grubenv ]; then
  load_env
fi
if [ "\${next_entry}" ] ; then
   set default="\${next_entry}"
   set next_entry=
   save_env next_entry
fi

EOF
) >> $grub_cfg

if [ "$demo_type" = "DIAG" ] ; then
    # Make sure ONIE install mode is the default boot mode for the
    # diag partition.
    cat <<EOF >> $grub_cfg
set default=ONIE
EOF
    /mnt/onie-boot/onie/tools/bin/onie-boot-mode -q -o install
fi

# Add a menu entry for the DEMO OS
demo_grub_entry="Demo $demo_type"
(cat <<EOF
menuentry '$demo_grub_entry' {
        search --no-floppy --label --set=root $demo_volume_label
        echo    'Loading ONIE Demo $demo_type ...'
        linux   /demo.vmlinuz $GRUB_CMDLINE_LINUX DEMO_TYPE=$demo_type
        echo    'Loading ONIE initial ramdisk ...'
        initrd  /demo.initrd
}
EOF
) >> $grub_cfg

if [ "$demo_type" = "OS" ] ; then
    # If there is a diag image add a chainload entry for it.
    diag_label=$(blkid | grep -- '-DIAG"' | sed -e 's/^.*LABEL="//' -e 's/".*$//')
    if [ -n "$diag_label" ] ; then
        onie_platform="$(onie-sysinfo -p)"
        cat <<EOF >> $grub_cfg
menuentry '$diag_label $onie_platform' {
        search --no-floppy --label --set=root $diag_label
        echo    'Loading $diag_label $onie_platform ...'
        chainloader +1
}
EOF
    fi
fi

# Add menu entries for ONIE -- use the grub fragment provided by the
# ONIE distribution.
/mnt/onie-boot/onie/grub.d/50_onie_grub >> $grub_cfg

cp $grub_cfg $demo_mnt/grub/grub.cfg

# clean up
umount $demo_mnt || {
    echo "Error: Problems umounting $demo_mnt"
}

cd /
