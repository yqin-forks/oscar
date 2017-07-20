#!/bin/sh
#
# Copyright (c) 2004-2005 The Trustees of Indiana University and Indiana
#                         University Research and Technology
#                         Corporation.  All rights reserved.
# Copyright (c) 2004-2005 The University of Tennessee and The University
#                         of Tennessee Research Foundation.  All rights
#                         reserved.
# Copyright (c) 2004-2005 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2004-2005 The Regents of the University of California.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

srcfile="$1"
option="$2"

case "$option" in
    # svnversion can take a while to run.  If we don't need it, don't run it.
    --major|--minor|--release|--greek|--base|--help)
        OSCAR_NEED_SVN=0
        ;;
    --nightly|*)
        OSCAR_NEED_SVN=1
esac


if test "$srcfile" = ""; then
    option="--help"
else
    if [ ! -e $srcfile ]; then
        option="--help"
    else
        OSCAR_MAJOR_VERSION="`cat $srcfile | egrep '^major=' | cut -d= -f2`"
        OSCAR_MINOR_VERSION="`cat $srcfile | egrep '^minor=' | cut -d= -f2`"
        OSCAR_RELEASE_VERSION="`cat $srcfile | egrep '^release=' | cut -d= -f2`"
        OSCAR_GREEK_VERSION="`cat $srcfile | egrep '^greek=' | cut -d= -f2`"
        OSCAR_WANT_BUILD_R="`cat $srcfile | egrep '^want_build_r=' | cut -d= -f2`"
        OSCAR_BUILD_R="`cat $srcfile | egrep '^build_r=' | cut -d= -f2`"
        if test "$OSCAR_RELEASE_VERSION" != "0" -a "$OSCAR_RELEASE_VERSION" != ""; then
	        OSCAR_VERSION="$OSCAR_MAJOR_VERSION.$OSCAR_MINOR_VERSION.$OSCAR_RELEASE_VERSION"
        else
	        OSCAR_VERSION="$OSCAR_MAJOR_VERSION.$OSCAR_MINOR_VERSION"
        fi

        OSCAR_VERSION="${OSCAR_VERSION}${OSCAR_GREEK_VERSION}"

        OSCAR_BASE_VERSION="$OSCAR_VERSION"

        OSCAR_DATE=`date '+%Y%m%d'`

        if test "$OSCAR_WANT_BUILD_R" = "1" -a "$OSCAR_NEED_SVN" = "1" ; then
            if test "$OSCAR_BUILD_R" = "-1"; then
                if test -d .git; then
                    ver="r`git rev-list --all HEAD|wc -l`" # --count not available in git 1.7.1
                else
                    ver="svn`date '+%Y%d%m'`"
                fi
                OSCAR_BUILD_R="$ver"
            fi
	        OSCAR_VERSION="${OSCAR_VERSION}$OSCAR_BUILD_R"
        fi

        if test "$option" = ""; then
	        option="--full"
        fi
    fi
fi

OSCAR_BUILD_R=`echo $OSCAR_BUILD_R | sed -e 's/nightly//g' | cut -d- -f1`
case "$option" in
    --full|-v|--version)
	echo $OSCAR_VERSION
	;;
    --major)
	echo $OSCAR_MAJOR_VERSION
	;;
    --minor)
	echo $OSCAR_MINOR_VERSION
	;;
    --release)
	echo $OSCAR_RELEASE_VERSION
	;;
    --greek)
	echo $OSCAR_GREEK_VERSION
	;;
    --build-r)
	echo $OSCAR_BUILD_R
	;;
    --base)
        echo $OSCAR_BASE_VERSION
        ;;
    --all)
        echo ${OSCAR_VERSION} ${OSCAR_MAJOR_VERSION} ${OSCAR_MINOR_VERSION} ${OSCAR_RELEASE_VERSION} ${OSCAR_GREEK_VERSION} ${OSCAR_BUILD_R}
        ;;
    --nightly)
	echo ${OSCAR_VERSION}nightly-${OSCAR_DATE}
	;;
    -h|--help)
	cat <<EOF
$0 <srcfile> [<option>]

<srcfile> - Text version file
<option>  - One of:
    --full    - Full version number
    --major   - Major version number
    --minor   - Minor version number
    --release - Release version number
    --greek   - Greek (alpha, beta, etc) version number
    --build-r - git HEAD commit count
    --all     - Show all version numbers, separated by :
    --base    - Show base version number (no git number)
    --nightly - Return the version number for nightly tarballs
    --help    - This message
EOF
        ;;
    *)
        echo "Unrecognized option $option.  Run $0 --help for options"
        ;;
esac

# All done

exit 0
