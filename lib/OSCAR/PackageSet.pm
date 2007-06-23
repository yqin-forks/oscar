package OSCAR::PackageSet;
#
# Copyright (c) 2007 Geoffroy Vallee <valleegr@ornl.gov>
#                    Oak Ridge National Laboratory
#                    All rights reserved.
#
#   $Id: PackageSet.pm 4833 2006-05-24 08:22:59Z bli $
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

use strict;
use vars qw(@EXPORT @PKG_SOURCE_LOCATIONS);
use base qw(Exporter);
use OSCAR::OCA::OS_Detect;
use OSCAR::Utils qw ( print_array );
use XML::Simple;
use Data::Dumper;
use Carp;

@EXPORT = qw(
            get_local_package_set_list
            get_list_opkgs_in_package_set
            get_opkgs_path_from_package_set
            );

my $verbose = $ENV{OSCAR_VERBOSE};
my $package_set_dir = $ENV{OSCAR_HOME}."/share/package_sets";

###############################################################################
# Scan package sets defined in share/package_sets based on the local
# distribution id. For instance, on debian 4 i386, we will look into the file
# share/package_sets/<pkg_set>/debian-4-i386.xml.
# Parameter: none.
# Return:    list of package sets. Note that we skip Default which is used by
#            default.
###############################################################################
sub get_local_package_set_list {
    my @packageSets = ();
    die ("ERROR: The package set directory does not exist ".
        "($package_set_dir)") if ( ! -d $package_set_dir );

    opendir (DIRHANDLER, "$package_set_dir")
        or die ("ERROR: Impossible to open $package_set_dir");
    foreach my $dir (sort readdir(DIRHANDLER)) {
        # We skip few directories. Note that we skip Default because we 
        # _always_ use it later (default is default!).
        if ($dir eq "." or $dir eq ".." or $dir eq "Default") {
            next;
        } else {
            print "Analyzing package set \"$dir\"\n" if $verbose;
            my $os = OSCAR::OCA::OS_Detect::open();
            # When we find a package set, we check if a package set is really
            # defined for the local distro. Note that the list of supported OPKG
            # supported by the local distro directly impact the list of avaiable
            # OPKGs, even if users wants to create images based on other distro.
            # This is normal, we must be sure the headnode provides all necessary
            # services (provided via OPKGs).
            my $distro_id = $os->{distro} . "-" . $os->{distro_version} . "-" .
                            $os->{arch} . ".xml";
            if ( -f "$package_set_dir/$dir/$distro_id") {
                print "Package set found: $dir\n" if $verbose;
                push (@packageSets, $dir);
            }
        }
    }
    closedir (DIRHANDLER);

    return @packageSets;
}

###############################################################################
# Give the set of OPKGs present in a specific package set
# Parameter: Package set name.
# Return:    List of OPKGs
###############################################################################
sub get_list_opkgs_in_package_set {
    my ($packageSetName) = @_;

    die ("ERROR: The package set directory does not exist ".
        "($package_set_dir)") if ( ! -d $package_set_dir );
    my $os = OSCAR::OCA::OS_Detect::open();
    my $distro_id = $os->{distro} . "-" . $os->{distro_version} . "-" .
                    $os->{arch} . ".xml";
    my $file_path = "$package_set_dir/$packageSetName/$distro_id";
    die ("ERROR: Impossible to read the package set ($file_path)") 
        if ( ! -f $file_path);

    my @opkgs = ();

    # If the package set file exist, we parse the file
    open (FILE, "$file_path") or die ("ERROR: impossible to open $file_path");
    my $simple= XML::Simple->new (ForceArray => 1);
    my $xml_data = $simple->XMLin($file_path);
    my $base = $xml_data->{packages}->[0]->{opkg};
    print Dumper($xml_data) if $verbose;
    print "Number of OPKG in the $packageSetName package set: ".
          scalar(@{$base})."\n" if $verbose;
    # When we have the list of OPKG, we check that the directories exist
    print "Validating package set $packageSetName...\n" if $verbose;
    my $opkg_directory = $ENV{OSCAR_HOME}."/packages/";
    for (my $i=0; $i < scalar(@{$base}); $i++) {
        my $opkg_name = $xml_data->{packages}->[0]->{opkg}->[$i];
        my $dir = $opkg_directory . $opkg_name;
        if ( -d $dir) {
            print "Package $opkg_name valid...\n" if $verbose;
            push (@opkgs, $opkg_name);
        } else {
            print "Package $opkg_name is not valid, we exclude it ($dir)\n"
                if $verbose;
        }
    }
    
    if ($verbose) {
        print "List of available OPKGs: ";
        print_array (@opkgs);
    }
    return @opkgs;
}

###############################################################################
# Give the set of OPKGs (with their full path) present in a specific package 
# set.
# This is used when other OSCAR components wants to check that the directory 
# for a specific OPKG exists (e.g. OPD related stuff)
# Parameter: Package set name.
# Return:    List of OPKGs
###############################################################################
sub get_opkgs_path_from_package_set {
    my ($packageSetName) = @_;

    die ("ERROR: The package set directory does not exist ".
        "($package_set_dir)") if ( ! -d $package_set_dir );
    my $os = OSCAR::OCA::OS_Detect::open();
    my $distro_id = $os->{distro} . "-" . $os->{distro_version} . "-" .
                    $os->{arch} . ".xml";
    my $file_path = "$package_set_dir/$packageSetName/$distro_id";
    die ("ERROR: Impossible to read the package set ($file_path)")
        if ( ! -f $file_path);

    my @opkgs = ();

    # If the package set file exist, we parse the file
    open (FILE, "$file_path");
    my $simple= XML::Simple->new (ForceArray => 1);
    my $xml_data = $simple->XMLin($file_path);
    my $base = $xml_data->{packages}->[0]->{opkg};
    print Dumper($xml_data) if $verbose;
    print "Number of OPKG in the $packageSetName package set: ".
          scalar(@{$base})."\n" if $verbose;
    # When we have the list of OPKG, we check that the directories exist
    print "Validating package set $packageSetName...\n" if $verbose;
    my $opkg_directory = $ENV{OSCAR_HOME}."/packages/";
    for (my $i=0; $i < scalar(@{$base}); $i++) {
        my $opkg_name = $xml_data->{packages}->[0]->{opkg}->[$i];
        my $dir = $opkg_directory . $opkg_name;
        if ( -d $dir) {
            print "Package $opkg_name valid...\n" if $verbose;
            push (@opkgs, $dir);
        } else {
            print "Package $opkg_name is not valid, we exclude it ($dir)\n"
                if $verbose;
        }
    }

    print "List of available OPKGs: ";
    print_array (@opkgs);
    return @opkgs;
}