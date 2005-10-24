#!/usr/bin/env perl
#
# Copyright (c) 2005 The Trustees of Indiana University.  
#                    All rights reserved.
# 
# This file is part of the OSCAR software package.  For license
# information, see the COPYING file in the top level directory of the
# OSCAR source distribution.
#
# $HEADER$
#
# $Id$
#

package OCA::OS_Detect::RedHat;

use strict;
use POSIX;
use Config;

# This is the logic that determines whether this component can be
# loaded or not -- i.e., whether we're on a RHEL machine or not.

# Check uname

my ($sysname, $nodename, $release, $version, $machine) = POSIX::uname();

# We only support Linux -- if we're not Linux, then quit

return 0 if ("Linux" ne $sysname);

my $redhat_release;
my $distro;
my $update;

# If /etc/redhat-release exists, continue, otherwise, quit.

if (-e "/etc/redhat-release") {
	$redhat_release = `cat /etc/redhat-release`;
} else {
	return 0;
}

# We only support RHEL AS|WS 3 Update [2, 3, 5] and RHEL AS|WS 4
# Update 1, otherwise quit.

if ($redhat_release =~ 'release 3' &&
    $redhat_release =~ m/Update [2 3 5]/ ) {
    $update = $redhat_release;
    $update =~ s/(.*)(Update )(\d)\)/update-$3/;
} elsif ($redhat_release =~ 'release 4' &&
         $redhat_release =~ m/Update 1/ ) {
    $update = $redhat_release;
    $update =~ s/(.*)(Update )(\d)\)/update-$3/;
} else {
    return 0;
}

if ($redhat_release =~ /Red Hat Enterprise Linux AS/ ) {
    $distro = "redhat-el-as";
} elsif ( $redhat_release =~ /Red Hat Enterprise Linux WS/ ) {
    $distro = "redhat-el-ws";
} else {
    return 0;
}

# First set of data

our $id = {
    os => "linux",
    arch => $machine,
    os_release => $release,
    linux_distro => $distro,
    linux_distro_version => 3,
    distro_update => $update
};

# Make final string

$id->{ident} = "$id->{os}-$id->{arch}-$id->{os_release}-$id->{linux_distro}-$id->{linux_distro_version}-$id->{distro_update}";

# Once all this has been setup, whenever someone invokes the "query"
# method on this component, we just return the pre-setup data.

sub query {
    our $id;
    return $id;
}

# If we got here, we're happy

1;
