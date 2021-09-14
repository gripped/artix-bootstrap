#!/bin/bash

set -e -u -o pipefail

inits=('openrc' 'runit' 's6' 'suite66')

rm -rf --one-file-system download
for init in "${inits[@]}"
do
	./artix-bootstrap.sh -i $init -d download rootfs-$init
	pushd rootfs-$init
	rm var/cache/pacman/pkg/*
	tar -cpzf ../rootfs.$init.tar.gz *
	popd
	rm -rf --one-file-system rootfs-$init
done

