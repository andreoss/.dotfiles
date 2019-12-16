#!/bin/sh

# Dependencies:
# parted gptfdisk dosfstools e2fsprogs cryptsetup perl xfsprogs btrfs-progs

set -u

GUEST_ROOT_MOUNT=/new-root
DO_FORMAT=
DO_MOUNT=
DO_UNMOUNT=
DO_CHROOT=
DO_CRYPT=
FILESYSTEM="btrfs"

die() {
	echo "FATAL: $*" >&2
	exit 1
}

error() {
	printf "%s\n" "$*" >&2
	die
}

mb_to_sectors() {
	_megabytes="${1:?arg}"
	_sector_offset="${2:-0}"
	_bytes=$((_megabytes * 1024 * 1024))
	_aligned=$((_bytes - (_bytes % 2048)))
	_sectors=$((_aligned / 512 + _sector_offset))
	echo "${_sectors}s"
}

PART_GAP=$(mb_to_sectors 64)
BOOT_PART_END=$(mb_to_sectors 256)
BOOT_END_GAP=$(mb_to_sectors 320)
SYSTEM_PART_SIZE="41%"
EPHEMERAL=
LUKS_VERSION=luks1
GUEST_HOSTNAME="${GUEST_HOSTNAME:-localhost}"
GUEST_HEXID=$(printf '%s' "$GUEST_HOSTNAME" | sha256sum | cut -c1-8)

USER_STORAGE_PATH=/user

if [ "$USER" != "root" ]; then
	printf "Root required. Run it as:\n" >&2
	printf "\tsudo $0 $*\n" >&2
	exit 1
fi

while getopts "d:r:mufxC:F:B:N:H:S:" opt; do
	case "$opt" in
	d)
		DISK_DEVICE="$OPTARG"
		;;
	r)
		GUEST_ROOT_MOUNT="$OPTARG"
		;;
	H)
		GUEST_HOSTNAME="$OPTARG"
		GUEST_HEXID=$(printf '%s' "$GUEST_HOSTNAME" | sha256sum | cut -c1-8)
		;;
	m)
		DO_MOUNT=1
		;;
	u)
		DO_UNMOUNT=1
		;;
	f)
		DO_FORMAT=1
		;;
	x)
		DO_CHROOT=1
		;;
	C)
		DO_CRYPT=1
		;;
	F)
		FILESYSTEM="$OPTARG"
		;;
	E)
		EPHEMERAL=1
		;;
	B)
		BOOT_PART_END="$OPTARG"
		;;
	N)
		SYSTEM_PART_SIZE="$OPTARG"
		;;
	S)
		SWAP_SIZE_GB="$OPTARG"
		;;
	h | '?')
		echo "Usage: $0 -d DEVICE [-f] [-m] [-u] [-x] [-C] [-F fs] [-H hostname] [-B boot_end] [-N sys_size] [-S swap_gb] [-r root]"
		echo "  -d DEVICE      Disk device (required)"
		echo "  -f             Format disk"
		echo "  -m             Mount partitions"
		echo "  -u             Unmount partitions"
		echo "  -x             Chroot into mounted root"
		echo "  -C             Enable LUKS encryption"
		echo "  -F FS          Filesystem: btrfs, ext4, xfs (default: btrfs)"
		echo "  -H HOSTNAME    Guest hostname (default: localhost, hex ID derived via sha256)"
		echo "  -B BOOT_END    Boot partition end (sectors, or 0 to skip)"
		echo "  -N SYS_SIZE    System partition size (percentage or sectors)"
		echo "  -S SWAP_GB     Swap size in GB (default: max(mem, 16GB))"
		echo "  -r ROOT        Root mount point (default: /new-root)"
		die
		;;
	esac
done

case "$FILESYSTEM" in
btrfs | ext4 | xfs) ;;
*) error "Unsupported filesystem: $FILESYSTEM (use btrfs, ext4, or xfs)" ;;
esac

check_if_mounted() {
	if [ -z "$DISK_DEVICE" ]; then
		error "Disk device not specified. Use -d DEVICE"
	fi
	if mount | grep -q "^$DISK_DEVICE"; then
		error "$DISK_DEVICE is mounted"
	fi
}

calc_swap_size_gb() {
	if [ -n "${SWAP_SIZE_GB:-}" ]; then
		echo "$SWAP_SIZE_GB"
		return
	fi
	_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
	_mem_gb=$(((_mem_kb + 1048575) / 1048576))
	if [ "$_mem_gb" -gt 16 ]; then
		echo "$_mem_gb"
	else
		echo "16"
	fi
}

SWAP_SIZE_GB=$(calc_swap_size_gb)
SWAP_PART_MB=$((SWAP_SIZE_GB * 1024))
SWAP_PART_SECTORS=$(mb_to_sectors "$SWAP_PART_MB")

# UUID generation without collision checks (we wipe disk first)
gen_part_uuid() {
	_num="$1"
	_prefix=$(printf '%.4s' "$GUEST_HEXID")
	printf '%s0000-0000-0000-0000-00000000000%s' "$_prefix" "$_num"
}

gen_fs_uuid() {
	_num="$1"
	_prefix=$(printf '%.4s' "$GUEST_HEXID")
	printf '%sffff-ffff-ffff-ffff-fffffffffff%s' "$_prefix" "$_num"
}

PARTUUID_BOOT=$(gen_part_uuid 1)
PARTUUID_SYSTEM=$(gen_part_uuid 2)
PARTUUID_USER=$(gen_part_uuid 3)
PARTUUID_SWAP=$(gen_part_uuid 4)

FSUUID_SYSTEM=$(gen_fs_uuid 1)
FSUUID_USER=$(gen_fs_uuid 2)
FSUUID_BOOT=$(gen_fs_uuid 3)
FSUUID_SWAP=$(gen_fs_uuid 4)

crypt_label() {
	echo "$1-${GUEST_HEXID}"
}

crypt_key() {
	_name="$1"
	_key_file=secrets/$(crypt_label "$_name")
	if [ ! -e "$_key_file" ]; then
		mkdir -p "$(dirname "$_key_file")"
		dd if=/dev/urandom of="$_key_file" count=1 bs=1K 2>/dev/null
		chmod 400 "$_key_file"
	fi
	echo "$_key_file"
}

if [ "$DO_CRYPT" ]; then
	LUKS_KEY_FILE=$(crypt_key system)
	LUKS_MAPPER_NAME=$(crypt_label system)
fi

ROOT_DEVICE=
SYSTEM_DEVICE=
USER_DEVICE=
SWAP_DEVICE=

if [ "$DO_CRYPT" ]; then
	ROOT_DEVICE=/dev/mapper/"${LUKS_MAPPER_NAME}"
	SYSTEM_DEVICE="$ROOT_DEVICE"
else
	ROOT_DEVICE=/dev/disk/by-uuid/"${FSUUID_SYSTEM}"
	SYSTEM_DEVICE=/dev/disk/by-partuuid/"$PARTUUID_SYSTEM"
	USER_DEVICE=/dev/disk/by-partuuid/"$PARTUUID_USER"
fi
SWAP_DEVICE=/dev/disk/by-partuuid/"$PARTUUID_SWAP"

crypt_format_part() {
	_fs_uuid="$1"
	_part_uuid="$2"
	_name="$3"

	cryptsetup -q luksFormat --type "$LUKS_VERSION" --uuid "$_fs_uuid" /dev/disk/by-partuuid/"$_part_uuid" "$(crypt_key "$_name")"
}

crypt_close_part() {
	_label=$(crypt_label "$1")
	if cryptsetup status "$_label" >/dev/null 2>&1; then
		if ! cryptsetup close "$_label"; then
			error "Failed to close LUKS device: $_label"
		fi
	fi
}

crypt_open_part() {
	_part_uuid="$1"
	_name="$2"

	_device=/dev/disk/by-partuuid/"$_part_uuid"
	if cryptsetup isLuks "$_device" 2>/dev/null; then
		cryptsetup -q open --key-file="$(crypt_key "$_name")" "$_device" "$(crypt_label "$_name")" ||
			cryptsetup open "$_device" "$(crypt_label "$_name")"
	else
		error "Not LUKS: $_device"
	fi
}

crypt_close_all() {
	if [ "$DO_CRYPT" ]; then
		crypt_close_part system
		if [ "$FILESYSTEM" != "btrfs" ]; then
			crypt_close_part user
		fi
	fi
}

crypt_format_all() {
	if [ "$DO_CRYPT" ]; then
		crypt_format_part "$FSUUID_SYSTEM" "$PARTUUID_SYSTEM" system
		if [ "$FILESYSTEM" != "btrfs" ]; then
			crypt_format_part "$FSUUID_USER" "$PARTUUID_USER" user
		fi
	fi
	sleep 3
}

crypt_open_all() {
	if [ "$DO_CRYPT" ]; then
		crypt_open_part "$PARTUUID_SYSTEM" system
		if [ "$FILESYSTEM" != "btrfs" ]; then
			crypt_open_part "$PARTUUID_USER" user
		fi
	fi
}

root_mount_all() {
	mkdir -p "$GUEST_ROOT_MOUNT"
	if [ "$EPHEMERAL" ]; then
		mount -t tmpfs none "$GUEST_ROOT_MOUNT"
	else
		fs_mount_root
	fi
	for _dir in /opt /var /usr /etc /boot /proc /sys /dev /run /run/shm; do
		mkdir -p "${GUEST_ROOT_MOUNT}${_dir}"
	done
	mount -t proc /proc "${GUEST_ROOT_MOUNT}"/proc
	mount --rbind /sys "${GUEST_ROOT_MOUNT}"/sys
	mount --make-rslave "${GUEST_ROOT_MOUNT}"/sys
	mount --rbind /dev "${GUEST_ROOT_MOUNT}"/dev
	mount --make-rslave "${GUEST_ROOT_MOUNT}"/dev
	mount --bind /run "${GUEST_ROOT_MOUNT}"/run
	mount --make-slave "${GUEST_ROOT_MOUNT}"/run
	for _dir in /run/shm /dev/shm; do
		mkdir -p "${GUEST_ROOT_MOUNT}${_dir}"
	done
	mount -t tmpfs -o nosuid,nodev,noexec shm "${GUEST_ROOT_MOUNT}"/dev/shm
	mount -t tmpfs -o nosuid,nodev,noexec shm "${GUEST_ROOT_MOUNT}"/run/shm
	chmod 1777 "${GUEST_ROOT_MOUNT}/dev/shm"
	chmod 1777 "${GUEST_ROOT_MOUNT}/run/shm"
}

root_unmount_all() {
	umount "${GUEST_ROOT_MOUNT}"/dev/pts 2>/dev/null || :
	umount "${GUEST_ROOT_MOUNT}"/dev/mqueue 2>/dev/null || :
	umount "${GUEST_ROOT_MOUNT}"/dev/shm 2>/dev/null || :
	umount "${GUEST_ROOT_MOUNT}"/dev 2>/dev/null || :
	umount "${GUEST_ROOT_MOUNT}"/proc 2>/dev/null || :
	umount "${GUEST_ROOT_MOUNT}"/run/shm 2>/dev/null || :
	umount "${GUEST_ROOT_MOUNT}"/run 2>/dev/null || :
	umount "${GUEST_ROOT_MOUNT}"/sys/firmware/efi/efivars 2>/dev/null || :
	umount "${GUEST_ROOT_MOUNT}"/sys 2>/dev/null || :
	umount "$GUEST_ROOT_MOUNT" 2>/dev/null || :
}

btrfs_subvol_name() {
	_mount_point="$1"
	if [ "$_mount_point" = "/" ]; then
		echo "root"
	else
		echo "$_mount_point" | perl -pE 's[^/][];s[/$][];tr[/][-]'
	fi
}

btrfs_subvol_create() {
	_tmp_mount=/tmp/btrfs-root-volume

	mkdir -p "$_tmp_mount"
	mount -o ssd,compress=zstd "$ROOT_DEVICE" "$_tmp_mount"
	for _mp in "$@"; do
		_subvol=$(btrfs_subvol_name "$_mp")
		btrfs subvolume create "$_tmp_mount/$_subvol"
	done
	umount "$_tmp_mount"
}

btrfs_subvol_mount() {
	_mount_point="$1"
	mkdir -p "$GUEST_ROOT_MOUNT"/"$_mount_point"
	mount -o subvol=$(btrfs_subvol_name "$_mount_point") "$ROOT_DEVICE" "$GUEST_ROOT_MOUNT"/"$_mount_point"
}

btrfs_prepare() {
	_dev=
	if [ "$DO_CRYPT" ]; then
		_dev="$ROOT_DEVICE"
	else
		_dev=/dev/disk/by-partuuid/"$PARTUUID_SYSTEM"
	fi
	mkfs.btrfs -f -U "$FSUUID_SYSTEM" "$_dev"

	sleep 3
	if [ ! "$EPHEMERAL" ]; then
		btrfs_subvol_create /
	fi
	for _mp in /usr /etc /opt /boot /var; do
		btrfs_subvol_create "$_mp"
	done
	btrfs_subvol_create "$USER_STORAGE_PATH"
}

btrfs_mount_root() {
	mkdir -p "$GUEST_ROOT_MOUNT"
	btrfs_subvol_mount /
}

btrfs_mount_rest() {
	for _mp in /usr /etc /opt /boot; do
		btrfs_subvol_mount "$_mp"
	done
	mkdir -p "$GUEST_ROOT_MOUNT"/boot/efi
	mount /dev/disk/by-partuuid/"$PARTUUID_BOOT" "$GUEST_ROOT_MOUNT"/boot/efi
	btrfs_subvol_mount "$USER_STORAGE_PATH"
}

btrfs_unmount_all() {
	umount "$GUEST_ROOT_MOUNT/boot/efi" 2>/dev/null || :
	for _mp in /usr /etc /opt /boot; do
		umount "${GUEST_ROOT_MOUNT}${_mp}" 2>/dev/null || :
	done
}

ext4_prepare() {
	_dev=
	if [ "$DO_CRYPT" ]; then
		_dev="$ROOT_DEVICE"
	else
		_dev=/dev/disk/by-partuuid/"$PARTUUID_SYSTEM"
	fi
	mkfs.ext4 -F -U "$FSUUID_SYSTEM" "$_dev"

	if [ "$USER_DEVICE" ]; then
		_user_dev=
		if [ "$DO_CRYPT" ]; then
			_user_dev=/dev/mapper/$(crypt_label user)
		else
			_user_dev=/dev/disk/by-partuuid/"$PARTUUID_USER"
		fi
		mkfs.ext4 -F -U "$FSUUID_USER" "$_user_dev"
	fi
}

ext4_mount_root() {
	mkdir -p "$GUEST_ROOT_MOUNT"
	mount -o defaults "$SYSTEM_DEVICE" "$GUEST_ROOT_MOUNT"
}

ext4_mount_rest() {
	if [ "$USER_DEVICE" ]; then
		mkdir -p "$GUEST_ROOT_MOUNT/$USER_STORAGE_PATH"
		mount -o defaults "$USER_DEVICE" "$GUEST_ROOT_MOUNT/$USER_STORAGE_PATH"
	fi
}

ext4_unmount_all() {
	if [ "$USER_DEVICE" ]; then
		umount "$GUEST_ROOT_MOUNT/$USER_STORAGE_PATH" 2>/dev/null || :
	fi
	umount "$GUEST_ROOT_MOUNT" 2>/dev/null || :
}

xfs_prepare() {
	_dev=
	if [ "$DO_CRYPT" ]; then
		_dev="$ROOT_DEVICE"
	else
		_dev=/dev/disk/by-partuuid/"$PARTUUID_SYSTEM"
	fi
	mkfs.xfs -f -m uuid="$FSUUID_SYSTEM" "$_dev"

	if [ "$USER_DEVICE" ]; then
		_user_dev=
		if [ "$DO_CRYPT" ]; then
			_user_dev=/dev/mapper/$(crypt_label user)
		else
			_user_dev=/dev/disk/by-partuuid/"$PARTUUID_USER"
		fi
		mkfs.xfs -f -m uuid="$FSUUID_USER" "$_user_dev"
	fi
}

xfs_mount_root() {
	mkdir -p "$GUEST_ROOT_MOUNT"
	mount -o defaults "$SYSTEM_DEVICE" "$GUEST_ROOT_MOUNT"
}

xfs_mount_rest() {
	if [ "$USER_DEVICE" ]; then
		mkdir -p "$GUEST_ROOT_MOUNT/$USER_STORAGE_PATH"
		mount -o defaults "$USER_DEVICE" "$GUEST_ROOT_MOUNT/$USER_STORAGE_PATH"
	fi
}

xfs_unmount_all() {
	if [ "$USER_DEVICE" ]; then
		umount "$GUEST_ROOT_MOUNT/$USER_STORAGE_PATH" 2>/dev/null || :
	fi
	umount "$GUEST_ROOT_MOUNT" 2>/dev/null || :
}

fs_prepare() {
	case "$FILESYSTEM" in
	btrfs) btrfs_prepare ;;
	ext4) ext4_prepare ;;
	xfs) xfs_prepare ;;
	esac
}

fs_mount_root() {
	case "$FILESYSTEM" in
	btrfs) btrfs_mount_root ;;
	ext4) ext4_mount_root ;;
	xfs) xfs_mount_root ;;
	esac
}

fs_mount_rest() {
	case "$FILESYSTEM" in
	btrfs) btrfs_mount_rest ;;
	ext4) ext4_mount_rest ;;
	xfs) xfs_mount_rest ;;
	esac
}

fs_unmount_all() {
	case "$FILESYSTEM" in
	btrfs) btrfs_unmount_all ;;
	ext4) ext4_unmount_all ;;
	xfs) xfs_unmount_all ;;
	esac
}

boot_prepare() {
	if [ "$BOOT_PART_END" = "0" ]; then
		return
	fi
	mkfs.vfat -F 32 -i "0x$(printf '%.8s' "$FSUUID_BOOT")" /dev/disk/by-partuuid/"$PARTUUID_BOOT" >/dev/null 2>&1 || die
}

boot_mount() {
	if [ "$BOOT_PART_END" = "0" ]; then
		return
	fi
	mkdir -p "$GUEST_ROOT_MOUNT"/boot/efi
	mount /dev/disk/by-partuuid/"$PARTUUID_BOOT" "$GUEST_ROOT_MOUNT"/boot/efi
}

boot_unmount() {
	if [ "$BOOT_PART_END" = "0" ]; then
		return
	fi
	umount "$GUEST_ROOT_MOUNT"/boot/efi 2>/dev/null || :
}

swap_prepare() {
	_dev=/dev/disk/by-partuuid/"$PARTUUID_SWAP"
	mkswap -U "$FSUUID_SWAP" "$_dev"
}

swap_enable() {
	swapon /dev/disk/by-partuuid/"$PARTUUID_SWAP"
}

swap_disable() {
	swapoff /dev/disk/by-partuuid/"$PARTUUID_SWAP" 2>/dev/null || :
}

storage_unmount() {
	fs_unmount_all
}

if [ "$DO_FORMAT" ]; then
	check_if_mounted
	dd if=/dev/zero of="$DISK_DEVICE" bs=1M count=10

	parted -s "$DISK_DEVICE" mklabel gpt
	if [ "$BOOT_PART_END" = "0" ]; then
		parted -a optimal "$DISK_DEVICE" mkpart primary ext2 "$PART_GAP" "$SYSTEM_PART_SIZE"
		sgdisk --partition-guid=1:"$PARTUUID_SYSTEM" "$DISK_DEVICE"
		parted "$DISK_DEVICE" name 1 system
	else
		parted -a optimal "$DISK_DEVICE" mkpart primary fat16 "$PART_GAP" "$BOOT_PART_END"
		parted -a optimal "$DISK_DEVICE" mkpart primary ext2 "$BOOT_END_GAP" "$SYSTEM_PART_SIZE"
		sgdisk --partition-guid=1:"$PARTUUID_BOOT" "$DISK_DEVICE"
		sgdisk --partition-guid=2:"$PARTUUID_SYSTEM" "$DISK_DEVICE"
		parted "$DISK_DEVICE" name 1 boot
		parted "$DISK_DEVICE" name 1 esp
		parted "$DISK_DEVICE" name 2 system
		if [ "$SYSTEM_PART_SIZE" != "100%" ]; then
			parted -a optimal "$DISK_DEVICE" mkpart primary ext2 "$SYSTEM_PART_SIZE" 100%
			sgdisk --partition-guid=3:"$PARTUUID_USER" "$DISK_DEVICE"
			parted "$DISK_DEVICE" name 3 user
		fi
	fi
	parted -a optimal "$DISK_DEVICE" mkpart primary linux-swap -"$SWAP_PART_SECTORS" 100%
	_part_num=$(parted -s "$DISK_DEVICE" print | tail -1 | awk '{print $1}')
	sgdisk --partition-guid="$_part_num":"$PARTUUID_SWAP" "$DISK_DEVICE"
	parted "$DISK_DEVICE" name "$_part_num" swap

	# Allow time for device mapping to settle after cryptographic setup
	sleep 3
	crypt_format_all
	crypt_open_all
	boot_prepare
	fs_prepare
	swap_prepare

	# Allow time for filesystems to be ready before closing crypto devices
	sleep 3
	crypt_close_all
fi

if [ "$DO_MOUNT" ]; then
	check_if_mounted
	crypt_open_all
	root_mount_all
	fs_mount_rest
	boot_mount
	swap_enable
fi

if [ "$DO_CHROOT" ]; then
	if [ ! -d "$GUEST_ROOT_MOUNT/bin" ] && [ ! -d "$GUEST_ROOT_MOUNT/usr/bin" ]; then
		error "$GUEST_ROOT_MOUNT does not appear to be a valid root filesystem"
	fi
	chroot "$GUEST_ROOT_MOUNT" "${SHELL:-/bin/sh}"
fi

if [ "$DO_UNMOUNT" ]; then
	swap_disable
	boot_unmount
	fs_unmount_all
	root_unmount_all
	crypt_close_all
fi
