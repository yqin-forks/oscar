#!/usr/bin/perl
# $Id$
#
# Copyright (c) 2006-2007 Oak Ridge National Laboratory.
#                         All rights reserved.
#
# This script checks if the network configuration on the headnode satifies OSCAR
# requirements.
#

BEGIN {
    if (defined $ENV{OSCAR_HOME}) {
        unshift @INC, "$ENV{OSCAR_HOME}/lib";
    }
}

use warnings;
use English '-no_match_vars';
use POSIX;

# NOTE: Use the predefined constants for consistency!
use OSCAR::SystemSanity;

my $rc = SUCCESS;
my $host_file = "/etc/hosts";

$ENV{LANG}="C";

################################################################################
# We check if the hostname is valid, i.e. does not return localhost or         #
# something similar. We also check if the host name is assigned to the         #
# loopback interface or not.                                                   #
# Parameter: None.                                                             #
# Return:    FAILURE if a problem is detected, SUCCESS else.                   #
################################################################################
sub check_hostname ($) {
    my $host_file = shift;
    my $hostname = (uname)[1];
    if ($hostname eq "") {
        print " ---------------------------------------\n";
        print " ERROR: Localhost name seems to be empty\n";
        print " ---------------------------------------\n";
        return FAILURE;
    }
    my ($shorthostname) = split(/\./,$hostname,2);
    if ($shorthostname eq "") {
        print " --------------------------------------\n";
        print " ERROR: shorthostname seems to be empty\n";
        print " --------------------------------------\n";
        return FAILURE;
    }
    my $dnsdomainname = `dnsdomainname`;
    chomp ($dnsdomainname);
    if ($shorthostname eq "localhost") {
        print " -----------------------------------\n";
        print " ERROR: hostname cannot be localhost\n";
        print " -----------------------------------\n";
        return FAILURE;
    }

    # the value of hostname should not to be assigned to the loopback
    # interface
    my $hostname_ip = get_host_ip ($hostname, $host_file);
    if ($hostname_ip eq "" || $hostname_ip eq FAILURE) {
        print " ----------------------------------------------\n";
        print " ERROR: Impossible get the IP for the hostname ($hostname) \n";
        print " ----------------------------------------------\n";
        return FAILURE;
    }
    if ($hostname_ip eq "127.0.0.1") {
        print " -------------------------------------------------\n";
        print " ERROR: your hostname ($hostname) is assigned to  \n";
        print " the loopback interface\n";
        print " Please assign it to your public network interface\n";
        print " updating $host_file\n";
        print " -------------------------------------------------\n";
        return FAILURE;
    }
    
    return SUCCESS;
}

################################################################################
# Check the configuration of the interface used by OSCAR. Note that if we find #
# problems, we only report warnings since this problem may exist only because  #
# it is the first time the user executes OSCAR.
# Parameter: None.                                                             #
# Return:    FAILURE if a problem is detected, SUCCESS else.                   #
################################################################################
sub check_oscar_interface ($) {
    my $host_file = shift;
    my $oscar_if;
    require OSCAR::ConfigFile;
    $oscar_if = OSCAR::ConfigFile::get_value ("/etc/oscar/oscar.conf",
                                              undef,
                                              "OSCAR_NETWORK_INTERFACE");
    # if a env variable is set, it overwrites the value from the config file.
    $oscar_if = $ENV{OSCAR_HEAD_INTERNAL_INTERFACE} 
        if defined $ENV{OSCAR_HEAD_INTERNAL_INTERFACE};
    my %nics;
    open IN, "netstat -nr | awk \'/\\./{print \$NF}\' | uniq |"
        || die "ERROR: Unable to query NICs\n";
    while( <IN> ) {
        next if /^\s/ || /^lo\W/;
        chomp;
        s/\s.*$//;
        $nics{$_} = 1;
    }
    close IN;

    if (! ($oscar_if && exists $nics{$oscar_if}) ) {
	if (!defined($oscar_if) || $oscar_if eq "") {
            $oscar_if = "<None>";
        }
        print " ------------------------------------------------------\n";
        print " WARNING: A valid NIC must be specified for the cluster\n";
        print " private network.\n";
        print " Valid NICs: ".join( ", ", sort keys %nics )."\n\n";
        print " You tried to use: " . $oscar_if . ".\n";
        print " This may be normal if this is the first time you \n";
        print " execute OSCAR.\n";
        print " ------------------------------------------------------\n";
        return WARNING;
    }

    # we check now the IP assgned to the interface used by OSCAR
    my $oscar_ip = get_host_ip ("oscar-server", $host_file);
    if ($oscar_ip eq FAILURE) {
        print " ----------------------------------------------------\n";
        print " WARNING: oscar-server is not defined in $host_file. \n";
        print " This may be normal if this is the first time you \n";
        print " execute OSCAR.\n";
        print " ----------------------------------------------------\n";
        return WARNING;
    }
    my $oscar_if_ip = `env LC_ALL=C /sbin/ifconfig $oscar_if | grep "inet addr:" | awk '{ print \$2 }' | sed -e 's/addr://'`;
    chomp ($oscar_if_ip);
    # the first time we execute OSCAR, /etc/hosts is not updated, it is 
    # normal
    if ($oscar_ip ne "" && ($oscar_ip ne $oscar_if_ip)) {
        print " ----------------------------------------------------\n";
        print " WARNING: it seems the interface used is not the one \n";
        print " assigned to OSCAR in $host_file. \n";
        print " This may be normal if this is the first time you \n";
        print " execute OSCAR.\n";
        print " ----------------------------------------------------\n";
        return WARNING;
    }

    return SUCCESS;
}

################################################################################
# This function check if a specific hostname is defined in /etc/hosts.         #
# Comments are ignored and only one entry should exist. If not, this is an     #
# error.                                                                       #
# Parameter: hostname                                                          #
# Return:    hostname IP if success                                            #
################################################################################
sub get_host_ip ($) {
    my $id = shift;

    my $count = 0;
    my $my_ip;
    local *IN;
    open IN, "$host_file" or die ("ERROR: impossible to open hosts file ($!)");
    while (<IN>) {
        chomp;
        next if /^\s*\#/; # We skip comments
        if (/\s+$id(\s|$|\.)/) {
            if (/^(\d+\.\d+\.\d+\.\d+)\s+/) {
                $count++;
                $my_ip = $1;
            }
        }
    }
    close IN;
    if ($count > 1 && $my_ip ne "") {
#         print " ---------------------------------------------------\n";
#         print " ERROR: the hostname $id is used more than one time \n";
#         print " in /etc/hosts                                      \n";
#         print " ---------------------------------------------------\n";
        return FAILURE;
    }
    if ($count == 0) {
# 	print " ---------------------------------------------------\n";
# 	print " ERROR: the hostname $id could not be found         \n";
# 	print " in /etc/hosts                                      \n";
# 	print " ---------------------------------------------------\n";
        return FAILURE;
    }
    return $my_ip;
}

my $res1 = check_hostname($host_file);
my $res2 = check_oscar_interface ($host_file);
if ($res1 eq FAILURE || $res2 eq FAILURE) { 
    $rc = FAILURE;
    print " -----------------------------------\n";
    print "  $0 \n";
    print "  Network configuration not correct \n";
    print " -----------------------------------\n";
} elsif ($res2 eq WARNING) {
    $rc = WARNING;
}
exit($rc);
