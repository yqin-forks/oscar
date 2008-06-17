package OSCAR::LSBreleaseParser;

#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.

#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.

#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Copyright (c) 2008, Geoffroy Vallee <valleegr at ornl dot gov>
#                     Oak Ridge National Laboratory.
#                     All rights reserved.
#

#
# $Id$
# This module parses the /etc/lsb-release if it exists, extract data and format
# it with the OS_Dectect syntax.
#

use strict;
use lib "$ENV{OSCAR_HOME}/lib";
use OSCAR::ConfigFile;
use OSCAR::Logger;
use OSCAR::Utils;
use Carp;
use warnings "all";

my $lsbrelease_file = "etc/lsb-release";

################################################################################
# Parses the /etc/lsb-release file and return the distribution ID following    #
# following the OS_Detect syntax.                                              #
#                                                                              #
# Input: root, root of the file system in which the /etc/lsb-release file is.  #
# Return: the distro ID (OS_Detect syntax), undef if error, empty string if    #
#         the /etc/lsb-release file does not exist.                            #
################################################################################
sub parse_lsbrelease ($) {
    my ($root) = @_;

    $lsbrelease_file = "$root/$lsbrelease_file";
    if ( ! -f $lsbrelease_file ) {
        oscar_log_subsection "INFO: no $lsbrelease_file file\n";
        return "";
    }
    my $distro = OSCAR::ConfigFile::get_value ($lsbrelease_file,
                                               undef,
                                               "DISTRIB_ID");
    if ( !defined $distro ) {
        carp "ERROR: Impossible to get the distro id from $lsbrelease_file";
        return undef;
    }

    my $version = OSCAR::ConfigFile::get_value ($lsbrelease_file,
                                                undef,
                                                "DISTRIB_RELEASE");
    if ( !defined $version ) {
        carp "ERROR: Impossible to get the dist version from $lsbrelease_file";
        return undef;
    }

    my $arch = OSCAR::Utils::get_local_arch();

    return lc("$distro-$version-$arch");
}

parse_lsbrelease("/");

1;