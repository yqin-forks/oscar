package OSCAR::Opkg;

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# (C)opyright Bernard Li <bli@bcgsc.ca>.
#             All Rights Reserved.
#
# (C)opyright Oak Ridge National Laboratory
#             Geoffroy Vallee <valleegr@ornl.gov>
#             All rights reserved
#
# (C)opyright Erich Focht <efocht@hpce.nec.com>.
#             All Rights Reserved.
#
# $Id: Opkg.pm 7035 2008-06-17 02:31:41Z valleegr $
#
# OSCAR Package module
#
# This package contains subroutines for common operations related to
# the handling of OSCAR Packages (opkg).
# [EF]: Some of the stuff in Packages.pm should be moved here!

use strict;
use lib "$ENV{OSCAR_HOME}/lib";
use vars qw(@EXPORT);
use base qw(Exporter);
use File::Basename;
use OSCAR::Database;
use OSCAR::PackagePath;
use Carp;

@EXPORT = qw(
            get_data_from_configxml
            get_list_opkg_dirs
            get_opkg_version_from_configxml
            opkg_print
            opkgs_install
            opkgs_install_server
            create_list_selected_opkgs
            );

my $verbose = $ENV{OSCAR_VERBOSE};

# name of OSCAR Package
my $opkg = basename($ENV{OSCAR_PACKAGE_HOME}) if defined ($ENV{OSCAR_PACKAGE_HOME});

# location of OPKGs shipped with OSCAR
my $opkg_dir = $ENV{OSCAR_HOME} . "/packages";

# Prefix print statements with "[package name]" 
sub opkg_print {
	my $string = shift;
	print("[$opkg] $string");
}

###############################################################################
# Get the list of OPKG available in $(OSCAR_HOME)/packages                    #
# Parameter: None.                                                            #
# Return:    Array of OPKG names.                                             #
###############################################################################
sub get_list_opkg_dirs {
    my @opkgs = ();
    die ("ERROR: The OPKG directory does not exist ".
        "($opkg_dir)") if ( ! -d $opkg_dir );

    opendir (DIRHANDLER, "$opkg_dir")
        or die ("ERROR: Impossible to open $opkg_dir");
    foreach my $dir (sort readdir(DIRHANDLER)) {
        if ($dir ne "." && $dir ne ".." && $dir ne ".svn" 
            && $dir ne "package.dtd") {
            push (@opkgs, $dir);
        }
    }
    return @opkgs;
}

###############################################################################
# Install the server part of the passed OPKGs on the local system             #
# Parameters:                                                                 #
#            type of opkg to be installed (one of api, server, client)        #
#            list of OPKGs.                                                   #
# Return:    none.     (should return some error some time...)                #
###############################################################################
sub opkgs_install {
    my ($type, @opkgs) = (@_);

    if (!scalar(@opkgs)) {
	croak("No opkgs passed!");
    }

    #
    # Detect OS of master node.
    #
    my $os = &distro_detect_or_die();

    #
    # Locate package pools and create the directories if they don't exist, yet.
    #
    my $oscar_pkg_pool = &OSCAR::PackagePath::oscar_repo_url(os=>$os);
    my $distro_pkg_pool = &OSCAR::PackagePath::distro_repo_url(os=>$os);

    # The code below should migrate into a package. It is used in
    # install_prereq in exactly the same way. Maybe to OSCAR::PackageSmart...?
    # [EF]
    eval("require OSCAR::PackMan");
    my $pm = OSCAR::PackageSmart::prepare_pools(($verbose?1:0),
                        $oscar_pkg_pool, $distro_pkg_pool);
    if (!$pm) {
        croak "\nERROR: Could not create PackMan instance!\n";
    }

    my $suffix = "";
    $suffix = ".noarch" if ($os->{pkg} eq "rpm");
    my @olist;
    if ($type eq "api") {
	@olist = map { "opkg-".$_.$suffix } @opkgs;
    } elsif ($type =~ /^(client|server)$/) {
	@olist = map { "opkg-".$_."-$type$suffix" } @opkgs;
    } else {
	croak("Unsupported opkg type: $type");
    }
    my ($err, @out) = $pm->smart_install(@olist);
    if (!$err) {
        print "Error occured during smart_install:\n";
        print join("\n",@out)."\n";
        exit 1;
    }
}

###############################################################################
# Get a list of the client binary packages that we want to install.  Make a   #
# new file containing the names of all the binary packages to install.        #
# This is used for the creation of a temporary file when we build a new       #
# image.                                                                      #
# Input: file where the list has to be written.                               #
# Return: none.
###############################################################################
sub create_list_selected_opkgs {
    my $outfile = shift;

    my @opkgs = list_selected_packages("all");
    open(OUTFILE, ">$outfile") or croak("Could not open $outfile");
    foreach my $opkg_ref (@opkgs) {
        my $opkg = $$opkg_ref{package};
        my $pkg = "opkg-".$opkg."-client";
        print OUTFILE "$pkg\n";
    }
    close(OUTFILE);
}

#
# Write group files which are ready to be used by SystemInstaller as
# additional package files.
#
sub write_pgroup_files {
    my (@pgroups, @groups_list, @errors);
    OSCAR::Database::get_groups_for_packages(\@groups_list, {}, \@errors);
    foreach my $groups_ref (@groups_list){
	push @pgroups, $$groups_ref{group_name};
    }
    foreach my $pset (@pgroups) {
	my (@res, @errs);
	&get_group_packages($pset, \@res, {}, \@errs);
	my $file = $OSCAR::PackagePath::PGROUP_PATH."/$pset.pgroup";
	print "Writing package group file for client installation: $file\n";
	local *OUT;
	open OUT, "> $file" or die "Could not write $file : $!";
	for my $p (@res) {
	    print OUT "opkg-".$p->{package}."-client\n";
	}
	close OUT;
    }
}

################################################################################
# Gets the version of a give OPKG parsing a config.xml file. For that we need  #
# to parse the OPKG changelog for that.                                        #
#                                                                              #
# Input: configxml, path to the config.xml file we need to parse in order to   #
#                   extract data.                                              #
# Return: the OPKG version, undef if error.                                    #
################################################################################
sub get_opkg_version_from_configxml ($) {
    my ($configxml) = @_;

    require OSCAR::FileUtils;
    my $ref = OSCAR::FileUtils::parse_xmlfile ($configxml);
    if (!defined $ref) {
        carp "ERROR: Impossible to parse XML file ($configxml)";
        return undef;
    }

    my $changelog_ref = $ref->{changelog}->{versionEntry};
    my @versions;
    foreach my $entry (@$changelog_ref) {
        push (@versions, "$entry->{version}") if defined $entry->{version};
    }

    require OSCAR::Utils;
    require OSCAR::VersionParser;
    my $max = $versions[0];
    foreach my $v (@versions) {
        if (OSCAR::VersionParser::version_compare (
            OSCAR::VersionParser::parse_version($max),
            OSCAR::VersionParser::parse_version($v)) < 0) {
            $max = $v;
        }
    }
    return $max;
}

################################################################################
# Get the value of a specific tag from a config.xml file. Note that this is a  #
# basic function, the tag has to be a first level tag, if not it won't work.   #
#                                                                              #
# Input: configxml, path to the config.xml file we need to parse.              #
#        key, XML tag we are to look for.                                      #
# Return: the value of the XML tag, undef if errors.                           #
################################################################################
sub get_data_from_configxml ($$) {
    my ($configxml, $key) = @_;

    require OSCAR::FileUtils;
    my $ref = OSCAR::FileUtils::parse_xmlfile ($configxml);
    if (!defined $ref) {
        carp "ERROR: Impossible to parse XML file ($configxml)";
        return undef;
    }

    my $provide = $ref->{$key};
    return $provide;
}

1;
