#!/bin/bash

set -e -u -o pipefail

inits=('openrc' 'runit' 's6' 'dinit')

rm -rf --one-file-system download
for init in "${inits[@]}"
do
	./artix-bootstrap.sh -i $init -d download rootfs-$init
	pushd rootfs-$init
	rm var/cache/pacman/pkg/*
	tar -cpzf ../artixlinux-bootstrap-$(date +'%Y.%m.%d')-$init-x86_64.tar.gz *
	popd
	rm -rf --one-file-system rootfs-$init
done

