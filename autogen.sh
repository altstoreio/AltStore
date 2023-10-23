#!/bin/sh
# Run this to generate all the initial makefiles, etc.

THEDIR=`pwd`
cd `dirname $0`
srcdir=`pwd`

DIE=0

(autoconf --version) < /dev/null > /dev/null 2>&1 || {
	echo
	echo "You must have autoconf installed to compile libxml."
	echo "Download the appropriate package for your distribution,"
	echo "or see http://www.gnu.org/software/autoconf"
	DIE=1
}

(libtoolize --version) < /dev/null > /dev/null 2>&1 ||
(glibtoolize --version) < /dev/null > /dev/null 2>&1 || {
	echo
	echo "You must have libtool installed to compile libxml."
	echo "Download the appropriate package for your distribution,"
	echo "or see http://www.gnu.org/software/libtool"
	DIE=1
}

(automake --version) < /dev/null > /dev/null 2>&1 || {
	echo
	DIE=1
	echo "You must have automake installed to compile libxml."
	echo "Download the appropriate package for your distribution,"
	echo "or see http://www.gnu.org/software/automake"
}

if test "$DIE" -eq 1; then
	exit 1
fi

test -f entities.c || {
	echo "You must run this script in the top-level libxml directory"
	exit 1
}

EXTRA_ARGS=
if test "x$1" = "x--system"; then
    shift
    prefix=/usr
    libdir=$prefix/lib
    sysconfdir=/etc
    localstatedir=/var
    if [ -d /usr/lib64 ]; then
      libdir=$prefix/lib64
    fi
    EXTRA_ARGS="--prefix=$prefix --sysconfdir=$sysconfdir --localstatedir=$localstatedir --libdir=$libdir"
    echo "Running ./configure with $EXTRA_ARGS $@"
else
    if test -z "$NOCONFIGURE" && test -z "$*"; then
        echo "I am going to run ./configure with no arguments - if you wish "
        echo "to pass any to it, please specify them on the $0 command line."
    fi
fi

if [ ! -d $srcdir/m4 ]; then
        mkdir $srcdir/m4
fi

# Replaced by autoreconf below
autoreconf -if -Wall

if ! grep -q pkg.m4 aclocal.m4; then
    cat <<EOF

Couldn't find pkg.m4 from pkg-config. Install the appropriate package for
your distribution or set ACLOCAL_PATH to the directory containing pkg.m4.
EOF
    exit 1
fi

cd $THEDIR

if test x$OBJ_DIR != x; then
    mkdir -p "$OBJ_DIR"
    cd "$OBJ_DIR"
fi

if test -z "$NOCONFIGURE"; then
    $srcdir/configure $EXTRA_ARGS "$@"
    if test "$?" -ne 0; then
        echo
        echo "Configure script failed, check config.log for more info."
    else
        echo
        echo "Now type 'make' to compile libxml2."
    fi
fi
