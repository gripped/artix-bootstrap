artix-bootstrap
==============

Bootstrap a base Artix Linux system from any GNU distro.

Install
=======

    # install -m 755 artix-bootstrap.sh /usr/local/bin/artix-bootstrap

Examples
=========

Create a base artix distribution in directory 'myartix':

    # artix-bootstrap myartix

The same but use init openrc and a given repository source:

    # artix-bootstrap -i openrc -r "http://mirror1.artixlinux.org/repos" myartix

Usage
=====

Once the process has finished, chroot to the destination directory (default user: root/root):

    # chroot destination

Note that some packages require some system directories to be mounted. Some of the commands you can try:

    # mount --bind /proc myartix/proc
    # mount --bind /sys myartix/sys
    # mount --bind /dev myartix/dev
    # mount --bind /dev/pts myartix/dev/pts
 
License
=======

This project is licensed under the terms of the MIT license
