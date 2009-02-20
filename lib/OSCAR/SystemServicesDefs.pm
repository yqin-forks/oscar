package OSCAR::SystemServicesDefs;

# $Id$
#
# Copyright (c) 2008-2009 Geoffroy Vallee <valleegr@ornl.gov>
#                         Oak Ridge National Laboratory.
#                         All rights reserved.

use strict;
use base qw(Exporter);

# TODO: we do not deal with the case where a service is not disabled/enabled
# for all 2, 3, 4, and 5 runlevels.
use constant SERVICE_DISABLED => 0;
use constant SERVICE_ENABLED  => 1;

# List of supported services
use constant SSH            => 'ssh';
use constant DHCP           => 'dhcp';
use constant MYSQL          => 'mysql';
use constant SI_MONITORD    => 'monitord';

# List of actions related to system services
use constant START      => 0;
use constant STOP       => 1;
use constant RESTART    => 2;

# List of service status
use constant STARTED    => 0;
use constant STOPPED    => 1;

my @ISA = qw(Exporter);

our @EXPORT = qw(
                SERVICE_DISABLED
                SERVICE_ENABLED
                SSH
                DHCP
                START
                STOP
                RESTART
                );

1;
