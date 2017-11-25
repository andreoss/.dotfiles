#!/usr/bin/env bash





# Dependencies:
# parted gptfdisk dosfstools e2fsprogs cryptsetup perl

set -u

ROOT=/new-root
FORMAT=
MOUNT=
UNMOUNT=
CRYPT=
FS=
LABEL="gpt"

die() {
    >&2 echo "FATAL"
    exit 1
}

mb_adjusted() {
    m="${1:?arg}"
    s="${2:-0}"
    m=$(($m * 1024 ** 2))
    m=$(($m - ($m %  2048)))
    m=$(($m / 512 + $s))
    echo "${m}s"
}

FIRST_PART_GAP=$(mb_adjusted 64)
BOOT_SIZE=$(mb_adjusted 256)
BOOT_END=$(mb_adjusted 320)
SYS_SIZE="41%"
EPHEMERAL=
LUKS_TYPE=luks1
HOST_ID=000f

USER_STORAGE=/user

error() {
	printf "$*" >/dev/stderr
	printf "\n" >/dev/stderr
	die
}

if [ "$USER" != "root" ]; then
	error "Root required. Run it as:\n\tsudo $0 $@"
fi

while getopts "d:r:mufCF:L:B:N:EH:" opt; do
	case "$opt" in
	L)
		case "$OPTARG" in
		mbr | msdos)
			LABEL=msdos
			;;
		efi | uefi | gpt)
			LABEL=gpt
			;;
		esac
		;;
	d)
		DEVICE="$OPTARG"
		;;
	r)
		ROOT="$OPTARG"
		;;
	H)
		HOST_ID=$(echo "$OPTARG" | perl -lE 'printf "%04x", int(<>) % 0xFFFF')
		;;
	m)
		MOUNT=1
		;;
	u)
		UNMOUNT=1
		;;
	f)
		FORMAT=1
		;;
	C)
		CRYPT=1
		;;
	F)
		FS="$OPTARG"
		;;
	E)
		EPHEMERAL=1
		;;
	B)
		BOOT_SIZE="$OPTARG"
		;;
	N)
		SYS_SIZE="$OPTARG"
		;;
	h | '?')
		echo "See $BASH_SOURCE"
		die
		;;
	esac
done

check_if_mounted() {
	if mount | grep "$DEVICE"; then
		echo >&2 "$DEVICE is mounted"
		die
	fi
}

__crypt_label() {
	echo "$1-${HOST_ID}"
}

__crypt_key() {
	local name
	local key_file
	name="$1"
	key_file=secrets/$(__crypt_label $name)
	if [ ! -e "$key_file" ]; then
		mkdir --parent "$(dirname "$key_file")"
		dd if=/dev/urandom of="$key_file" count=1 bs=1K
		chmod 400 "$key_file"
	fi
	echo "$key_file"
}

if [ "$CRYPT" ]; then
	LUKS_KEY=$(__crypt_key system)
fi

if [ "$CRYPT" ]; then
	LUKS_LABEL=$(__crypt_label system)
fi

PART_MSDOS_PREFIX=0000"${HOST_ID}"

__gen_id() {
	local type
	local name
	type="$1"
	num="$2"
	if [ "$type" = "gpt" ]; then
		printf "00000000-0000-0000-%s-%012x" "$HOST_ID" "$num"
	elif [ "$type" = "msdos" ]; then
		printf "0000%s-%02x" "$HOST_ID" "$num"
	else
		error "Label type: $type unknown"
	fi
}

if [ "$LABEL" = "gpt" ]; then
	PART_BOOT=$(__gen_id gpt 1)
	PART_SYSTEM=$(__gen_id gpt 2)
	PART_USER=$(__gen_id gpt 3)
elif [ "$LABEL" = "msdos" ]; then
	if [ "$BOOT_SIZE" = "0" ]; then
		PART_BOOT=
		PART_SYSTEM=$(__gen_id msdos 1)
		PART_USER=$(__gen_id msdos 2)
	else
		PART_BOOT=$(__gen_id msdos 1)
		PART_SYSTEM=$(__gen_id msdos 2)
		PART_USER=$(__gen_id msdos 3)
	fi
fi

ID_SYSTEM=ffffffff-ffff-ffff-"$HOST_ID"-000000000001
ID_BOOT_CRYPT=ffffffff-ffff-ffff-"$HOST_ID"-000000000002
ID_BOOT="$HOST_ID"-ffff
ID_USER=ffffffff-ffff-ffff-"$HOST_ID"-000000000003

BTRFS_DEVICE=
RAW_DEVICE=

if [ "$CRYPT" ]; then
	BTRFS_DEVICE=/dev/mapper/"${LUKS_LABEL}"
else
	BTRFS_DEVICE=/dev/disk/by-uuid/"${ID_SYSTEM}"
fi


USER_DEVICE=
if [ "$CRYPT" ]; then
	RAW_DEVICE="$BTRFS_DEVICE"
else
	RAW_DEVICE=/dev/disk/by-partuuid/"$PART_SYSTEM"
	USER_DEVICE=/dev/disk/by-partuuid/"$PART_USER"

fi

ROOT_MOUNT_POINT=
if [ ! "$EPHEMERAL" ]; then
	ROOT_MOUNT_POINT="$ROOT/"
else
	ROOT_MOUNT_POINT="$ROOT/"
fi

should_exists() {
	mkdir --parent "$@"
}

__crypt_format() {
	local fs_uuid part_uuid name
	fs_uuid="$1"
	part_uuid="$2"
	name="$3"

	cryptsetup -q luksFormat --type "$LUKS_TYPE" --uuid "$fs_uuid" /dev/disk/by-partuuid/"$part_uuid" "$(__crypt_key "$name")"
}

__crypt_close() {
	local label
	label=$(__crypt_label $1)
	if cryptsetup status "$label"; then
		cryptsetup close $label
	else
		error "Invalid LUKS label: $label"
	fi
}

__crypt_open() {
	local fs_uuid part_uuid name device
	part_uuid="$1"
	name="$2"

	device=/dev/disk/by-partuuid/"$part_uuid"
	if cryptsetup isLuks "$device"; then
		cryptsetup -q open --key-file="$(__crypt_key "$name")" "$device" "$(__crypt_label "$name")"
	else
		error "Not LUKS: $*"
	fi
}

crypt_close() {
	if [ "$CRYPT" ]; then
		__crypt_close system
		if [ "$FS" != "btrfs" ]; then
			__crypt_close user
		fi
	fi
}

crypt_format() {
	if [ "$CRYPT" ]; then
		__crypt_format "$ID_SYSTEM" "$PART_SYSTEM" system
		if [ "$FS" != "btrfs" ]; then
			__crypt_format "$ID_USER" "$PART_USER" user
		fi
	fi
	sleep 3
}

crypt_open() {
	if [ "$CRYPT" ]; then
		__crypt_open "$PART_SYSTEM" system
		if [ "$FS" != "btrfs" ]; then
			__crypt_open "$PART_USER" user
		fi
	fi
}

root_mount() {
	should_exists "$ROOT"
	if [ "$EPHEMERAL" ]; then
		mount -t tmpfs none "$ROOT"
	else
		echo "skip"
	fi
        for dir in /opt /var /usr /etc /boot
        do
            should_exists "${ROOT}${dir}"
        done
}

root_unmount() {
	umount "$ROOT"
}

btrfs_subvol_name() {
	local MOUNT_POINT="$1"
	if [ "$MOUNT_POINT" = "/" ]; then
		echo "root"
	else
		echo "$MOUNT_POINT" | perl -pE 's[^/][];s[/$][];tr[/][-]'
	fi

}

btrfs_subvol_create() {
	local ROOT_VOLUME=/tmp/btrfs-root-volume
	mkdir -p "$ROOT_VOLUME"
	mount -o ssd,compress=zstd "$BTRFS_DEVICE" "$ROOT_VOLUME"
	for MOUNT_POINT in "$@"; do
		local SUBVOL_NAME=$(btrfs_subvol_name "$MOUNT_POINT")
		btrfs subvolume create "$ROOT_VOLUME/$SUBVOL_NAME"
	done
	umount "$ROOT_VOLUME"
}

btrfs_subvol_mount() {
	local MOUNT_POINT="$1"
	should_exists "$ROOT"/"$MOUNT_POINT"
	mount -o subvol=$(btrfs_subvol_name "$MOUNT_POINT") "$BTRFS_DEVICE" "$ROOT"/"$MOUNT_POINT"
}

btrfs_prepare() {
	if [ "$CRYPT" ]; then
		mkfs.btrfs "$BTRFS_DEVICE" -f
	else
		mkfs.btrfs /dev/disk/by-partuuid/"$PART_SYSTEM" -f
	fi

	sleep 3
	if [ ! "$EPHEMERAL" ]; then
		btrfs_subvol_create /
	fi
        for mount_point in /usr /etc /opt /boot
        do
            btrfs_subvol_create "$mount_point"
        done
	btrfs_subvol_create "$USER_STORAGE"
}

btrfs_mount() {
	if [ ! "$EPHEMERAL" ]; then
		btrfs_subvol_mount /
	fi
        for mount_point in /usr /etc /opt /boot
        do
            btrfs_subvol_mount "$mount_point"
        done
	if [ "$LABEL" = "gpt" ]; then
		should_exists "$ROOT"/boot/efi
		mount /dev/disk/by-partuuid/"$PART_BOOT" "$ROOT"/boot/efi
	fi
	btrfs_subvol_mount "$USER_STORAGE"
}

btrfs_unmount() {
	if [ "$LABEL" = "gpt" ]; then
		umount "$ROOT/boot/efi"
	fi
        for mount_point in /usr /etc /opt /boot
        do
            umount "${ROOT}${mount_point}"
        done
}

boot_prepare() {
	if [ "$BOOT_SIZE" = "0" ]; then
		return
	fi
	if [ "$LABEL" = "gpt" ]; then
		mkfs.fat /dev/disk/by-partuuid/"$PART_BOOT"  -F 32 -I -i "${ID_BOOT//-/}"
	elif [ "$LABEL" = "msdos" ]; then
		if [ "$CRYPT" ]; then
			__crypt_format "$ID_BOOT_CRYPT" "$PART_BOOT" boot
			__crypt_open "$PART_BOOT" boot
			mkfs.ext3 -F /dev/mapper/$(__crypt_label boot) || die
			__crypt_close boot
		else
			mkfs.ext3 -F /dev/disk/by-partuuid/"$PART_BOOT"
		fi
	else
		error "$LABEL unsupported"
	fi
}

boot_mount() {
	if [ "$BOOT_SIZE" = "0" ]; then
		return
	fi
	if [ "$CRYPT" ] && [ "$LABEL" == "msdos" ]; then
		__crypt_open "$PART_BOOT" boot
		mount /dev/mapper/$(__crypt_label boot) "$ROOT"/boot
        elif [ "$LABEL" = "msdos" ]; then
            mount -t ext3 /dev/disk/by-partuuid/"$PART_BOOT" "$ROOT/boot"
	elif [ "$LABEL" = "gpt" ]; then
		should_exists "$ROOT"/boot/efi
		mount /dev/disk/by-partuuid/"$PART_BOOT" "$ROOT"/boot/efi
                return
	fi
}

boot_unmount() {
	if [ "$BOOT_SIZE" = "0" ]; then
		return
	fi
	if [ "$CRYPT" ]; then
		__crypt_close boot
        fi
        if [ "$LABEL" == "msdos" ]; then
            umount "$ROOT"/boot
	else
		umount "$ROOT"/boot/efi
	fi
}

f2fs_mount() {
	DEV_SYSTEM=
	DEV_USER=
	if [ "$CRYPT" ]; then
		DEV_SYSTEM=/dev/mapper/$(__crypt_label system)
		DEV_USER=/dev/mapper/$(__crypt_label user)
	else
		DEV_SYSTEM=/dev/disk/by-partuuid/"$PART_SYSTEM"
		DEV_USER=/dev/disk/by-partuuid/"$PART_USER"
	fi
	mount -o compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime "$DEV_SYSTEM" "$ROOT_MOUNT_POINT"
	mount -o compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime "$DEV_USER" "$ROOT/$USER_STORAGE"
	#chattr -R +c "$ROOT_MOUNT_POINT"
}

generic_mount() {
	mount "$RAW_DEVICE" "$ROOT_MOUNT_POINT"
        if [ "$USER_DEVICE" ]; then
            mount "$USER_DEVICE" "$ROOT/user"
        fi
}

generic_unmount() {
        if [ "$USER_DEVICE" ]; then
            umount "$ROOT/user"
        fi
	umount "$ROOT/$USER_STORAGE"
	umount "$ROOT_MOUNT_POINT"
}

storage_prepare() {
	case "$FS" in
	btrfs)
		btrfs_prepare
		;;
	*)
		echo "Unknown fs: $FS"
		exit
		;;
	esac
}

storage_mount() {
        for dir in /opt /var /usr /etc /boot
        do
            should_exists "${ROOT}${dir}"
        done
	case "$FS" in
	btrfs)
		btrfs_mount
		;;
	*)
		echo "Unknown fs: $FS"
		exit
		;;
	esac

}

storage_unmount() {
	case "$FS" in
	btrfs)
		btrfs_unmount
		;;
	*)
		echo "Unknown fs: $FS"
		exit
		;;
	esac
}

if [ "$FORMAT" ]; then
	check_if_mounted
	dd if=/dev/zero of="$DEVICE" bs=1M count=10

	if [ "$LABEL" = "gpt" ]; then
		parted -s "$DEVICE" mklabel "$LABEL"
		if [ "$BOOT_SIZE" = "0" ]; then
			parted -a optimal "$DEVICE" mkpart primary ext2 "$FIRST_PART_GAP" "$SYS_SIZE"
			sgdisk --partition-guid=1:"$PART_SYSTEM" "$DEVICE"
			parted "$DEVICE" name 1 system
		else
			parted -a optimal "$DEVICE" mkpart primary fat16 $FIRST_PART_GAP "$BOOT_SIZE"
			parted -a optimal "$DEVICE" mkpart primary ext2 "$BOOT_END" "$SYS_SIZE"
			sgdisk --partition-guid=1:"$PART_BOOT" "$DEVICE"
			sgdisk --partition-guid=2:"$PART_SYSTEM" "$DEVICE"
			parted "$DEVICE" name 1 boot
			parted "$DEVICE" name 1 esp
			parted "$DEVICE" name 2 system
                        if [ "$SYS_SIZE" != "100%" ]; then
                            parted -a optimal "$DEVICE" mkpart primary ext2 "$SYS_SIZE" 100%
                            sgdisk --partition-guid=3:"$PART_USER" "$DEVICE"
                            parted "$DEVICE" name 3 system
                        fi
		fi

	elif [ "$LABEL" = "msdos" ]; then
		parted -s "$DEVICE" mklabel "$LABEL" || die
		if [ "$BOOT_SIZE" = "0" ]; then
			parted -a optimal "$DEVICE" mkpart primary ext2 "$FIRST_PART_GAP" "$SYS_SIZE" || die
                        if [ "$SYS_SIZE" != "100%" ]; then
                            parted -a optimal "$DEVICE" mkpart primary ext2 "$SYS_SIZE" 100% || die
                        fi
		else
			parted -a optimal "$DEVICE" mkpart primary ext2 "$FIRST_PART_GAP" "$BOOT_SIZE" || die
			parted -a optimal "$DEVICE" mkpart primary ext2 "$BOOT_END"       "$SYS_SIZE"  || die
                        if [ "$SYS_SIZE" != "100%" ]
                        then
                            parted -a optimal "$DEVICE" mkpart primary ext2 "$SYS_SIZE" 100%  || die
                        fi
		fi

		fdisk --wipe "$DEVICE"
		(
			echo x                      # Expert mode
			echo i                      # Change disk indentifier
			echo 0x"$PART_MSDOS_PREFIX" # New identifier
			echo r                      # Return
			echo w                      # Write
			echo q                      # Quite
		) | fdisk "$DEVICE"
		parted "$DEVICE" set 1 boot on
		partx "$DEVICE"
	else
		error "$LABEL unsupported"
	fi

	sleep 3
	crypt_format
	crypt_open
	boot_prepare
	storage_prepare

	sleep 3
	crypt_close
fi

if [ "$MOUNT" ]; then
	check_if_mounted
	crypt_open
	root_mount
	storage_mount
	boot_mount
fi

if [ "$UNMOUNT" ]; then
	boot_unmount
	storage_unmount
	root_unmount
	crypt_close
fi
