package OSCAR::MAC;

#   $Id: MAC.pm,v 1.8 2002/05/24 19:36:15 brechin Exp $

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

#   Copyright 2001-2002 International Business Machines
#                       Sean Dague <japh@us.ibm.com>

use strict;
use Net::Netmask;
use vars qw($VERSION @EXPORT);
use Tk;
use Tk::Tree;
use Carp;
use SIS::Client;
use File::Copy;
use SIS::Adapter;
use OSCAR::Network;
use base qw(Exporter);
@EXPORT = qw(mac_window);

$VERSION = sprintf("%d.%02d", q$Revision: 1.8 $ =~ /(\d+)\.(\d+)/);

# %MAC = (
#                   'macaddr' => {client => 'clientname', order => 'order collected'}
#                 );
#                 client will be client name or undef for unassigned
#                 order will be a number

my %MAC = (); # mac will be -1 for unknown, machine name for known
my $ORDER = 1;
my $COLLECT = 0;
my $PINGPID = undef;

sub mac_window {
    my ($parent, $vars) = @_;

    my $window = $parent->Toplevel;
    $window->title("MAC Address Collection");
    
    my $instructions = $window->Message(-text => "MAC Address Collection Tool.  When a new MAC address is received on the network, it will appear in the left column.  To assign that MAC address to a machine highlight the address and the machine and click 'Assign MAC to Node'.", -aspect => 800);

    my $label = $window->Label(-text => "Not Listening to Network. Click 'Collect MAC Addresses' to start.");

    my $listbox = $window->ScrlListbox(
                                       -selectmode => 'single',
                                       -background => "white",
                                      );
    my $tree = $window->Scrolled("Tree",
                                 -background => "white",
                                 -itemtype => 'imagetext',
                                 -separator => '|',
                                 -selectmode => 'single',
                                );

    $instructions->pack($label);
    my $frame = $window->Frame();
    $frame->pack(-side => "bottom", -anchor => "w", -fill => "x", -expand => 0);

    $listbox->pack(-side => "left", -expand => 0, -fill => "y");
    $tree->pack(-side => "left", -expand => 1, -fill => "both", -anchor => "w");
    
    regenerate_tree($tree);

    my $start = $frame->Button(
                                   -text => "Collect MAC Addresses",
                                   -command => [\&begin_collect_mac, $window, $listbox, $$vars{interface}, $label],
                                   );
    my $stop = $frame->Button(
                                         -text => "Stop Collecting",
                                         -command => [\&end_collect_mac, $label],
                                         );
    my $exitbutton = $frame->Button(
                                     -text => "Close",
                                     -command => sub {end_collect_mac($label); $window->destroy},
                                    );
    my $assignbutton = $frame->Button(
                                      -text => "Assign Mac to Node",
                                      -command => [\&assign2machine, $listbox, $tree],
                                     );
    my $deletebutton = $frame->Button(
                                      -text => "Delete Mac from Node",
                                      -command => [\&clear_mac, $listbox, $tree],
                                     );
    my $dhcpbutton = $frame->Button(
                                    -text => "Configure DHCP Server",
                                    -command => [\&setup_dhcpd, $$vars{interface}],
                                   );
    my $bootfloppy = $frame->Button(
                                    -text => "Build Autoinstall Floppy",
                                    -command => sub {system("xterm -T 'Build Autoinstall Floppy' -e mkautoinstalldiskette");},
                                   );
    my $networkboot = $frame->Button(
                                     -text => "Setup Network Boot",
                                     -command => [\&run_setup_pxe, $window],
                                    );

    $start->grid($stop, $exitbutton, -sticky => "ew");
    $assignbutton->grid($deletebutton, $dhcpbutton, -sticky => "ew");
    my $label2 = $frame->Label(-text => "Below are commands to create a boot environment.\nYou can either boot from floppy or network");
    $label2->grid("-","-",-sticky => "ew");
    $bootfloppy->grid($networkboot, -sticky => "ew");
}

sub setup_dhcpd {
    my $interface = shift;
    clean_hostsfile() or (carp "Couldn't clean hosts file!",
                          return undef);
    
    carp "About to run setup_dhcpd";
    if(-e "/etc/dhcpd.conf") {
        copy("/etc/dhcpd.conf", "/etc/dhcpd.conf.oscarbak") or (carp "Couldn't backup dhcpd.conf file", 
                                                            return undef);
    }
    my ($ip, $broadcast, $netmask) = interface2ip($interface);
    !system("mkdhcpconf -o /etc/dhcpd.conf --interface=$interface --bootfile=pxelinux.0 --gateway=$ip") or (carp "Couldn't mkdhcpconf",
                                                             return undef);
    if(!-e "/var/lib/dhcp/dhcpd.leases") {
        open(OUT,">/var/lib/dhcp/dhcpd.leases") or (carp "Couldn't create dhcpd.leases files",
                                                    return undef);
        close(OUT);
    }
    !system("service dhcpd restart") or (carp "Couldn't restart dhcpd", 
                                         return undef);
    
    return 1;
}

sub clean_hostsfile {
    my $file = "/var/lib/systemimager/scripts/hosts";
    copy($file, "$file.bak") or (carp "Couldn't backup rsyncable hosts file!",
                                 and return undef);
    open(IN,"<$file.bak") or (carp "Couldn't open $file.bak for reading!",
                                 and return undef);
    open(OUT,">$file") or (carp "Couldn't open $file for writing!",
                                 and return undef);
    while(<IN>) {
        if(/^\#/) {
            print OUT $_;
        }elsif(/^([\d+\.]+).*\s([^\s\.]+)\s/) {
            print OUT "$1     $2\n";
        }
    }
    close(OUT);
    close(IN);
}

sub regenerate_tree {
    my ($tree) = @_;
    $tree->delete("all");
    $tree->add("|",-text => "All Clients",-itemtype => "text");
    my @clients = clientList();
    foreach my $client (@clients) {
        my $adapter = findAdapter($client->{NAME},"eth0");
        $tree->add("|".$client->{NAME}, -text => $client->{HOST}, -itemtype => "text");
        $tree->add("|".$client->{NAME} . "|mac", 
                   -text => $adapter->{NAME} . " mac = " . $adapter->{MAC}, -itemtype => "text");
        $tree->add("|".$client->{NAME} . "|ip" . $adapter->{NAME}, 
           -text => $adapter->{NAME} . " ip = " . $adapter->{IP_ADDR}, -itemtype => "text");
    }
    $tree->autosetmode;
}

sub message_window {
    
}

#sub assignwindow {
#    my ($parent) = @_;
#    my $window = $parent->Toplevel;
#    $window->title("Assign MAC Address");
#    my $listbox
    
#}

sub assign2machine {
    my ($listbox, $tree) = @_;
    my $mac = $listbox->get($listbox->curselection) or return undef;
    my $node = $tree->infoSelection() or return undef;
    my $client;
    if($node =~ /^\|([^\|]+)/) {
        print "I think node is '$1'\n";
        $client = findClient($1);
    } else {
        return undef;
    }
    my $adapter = findAdapter($client->{NAME},"eth0");
    $MAC{$mac}->{client} = $adapter->{IP_ADDR};
    $adapter->{MAC} = $mac;
    $adapter->update;
    regenerate_listbox($listbox);
    regenerate_tree($tree);
}

sub clear_mac {
    my ($listbox, $tree) = @_;
    my $node = $tree->infoSelection() or return undef;
    my $client;
    if($node =~ /^\|([^\|]+)/) {
        print "I think node is '$1'\n";
        $client = findClient($1);
    } else {
        return undef;
    }
    my $adapter = findAdapter($client->{NAME},"eth0");
    my $mac = $adapter->{MAC};

    # now put the mac back in the pool
    $MAC{$mac}->{client} = undef;
    $adapter->{MAC} = "";
    $adapter->update;
    regenerate_listbox($listbox);
    regenerate_tree($tree);
}

sub regenerate_listbox {
    my $listbox = shift;
    $listbox->delete(0,"end");
    foreach my $key (sort {$MAC{$a}->{order} <=> $MAC{$b}->{order}} keys %MAC) {
        if(!$MAC{$key}->{client}) {
            $listbox->insert("end",$key);
        }
    }
    $listbox->update;
}

# Ok, here is the problem.  This whole thing works great on a network with
# a bunch of traffic.  It sucks on a quiet one.  So when we start up the
# tcpdump command we also fork a broadcast ping to generate more
# traffic on the network.

sub start_ping {
    my $interface = shift;
    end_ping();
    my ($ip, $broad, $nm) = interface2ip($interface);
    my $network = new Net::Netmask($ip, $nm);
    my $pid = fork();
    if($pid) {
        $PINGPID = $pid;
    } else {
        open(STDOUT,">/dev/null");
        exec("ping -b " . $network->base);
    }
}

sub end_ping {
    if($PINGPID) {
        print "Attempting to kill $PINGPID\n";
        kill 15, $PINGPID;
        $PINGPID = undef;
    }
}

sub end_collect_mac {
    my $label = shift;
    $label->configure(-text => "Not Listening to Network. Click 'Collect MAC Addresses' to start.");
    $COLLECT = 0;
}

# Interesting enough Mandrake and RedHat seem to compile tcpdump
# differently.  The two regexes should work with both.  We may have to
# add additional lines for other versions of tcpdump.
#
# The real solution is using Net::RawIP... but figuring out how that bad
# boy works is a full time job itself.

sub begin_collect_mac {
    return if $COLLECT; # This is so we don't end up with 2 tcpdump processes
    $COLLECT = 1;
    my ($window, $listbox, $interface, $label) = @_;
    start_ping($interface);
    my $cmd = "/usr/sbin/tcpdump -i $interface -n -e -l";
    open(TCPDUMP,"$cmd |") or (carp("Could not run $cmd"), return undef);
    $label->configure(-text => "Currently Scanning Network... Click 'Stop Collecting' to stop.");
    while($COLLECT and $_ = <TCPDUMP>) {
        # print $_ unless $_ =~ /echo/;
        # This is the for tcp dump version 3.6 (MDK 8.0)
        if(/^\S+\s+([a-f0-9\:]{11,17}).*bootp.*\(DF\)/) {
            my $mac = mactransform($1);
            if(add_mac_to_hash($mac)) {
                regenerate_listbox($listbox);
            }
        } 
        # This is for tcp dump version 3.4 (RH 7.1)
        elsif (/^\S+\s+\S\s+([a-f0-9\:]{11,17}).*\[\|bootp\]/) {
            my $mac = mactransform($1);
            if(add_mac_to_hash($mac)) {
                regenerate_listbox($listbox);
            }
        }
        # This is for tcp dump version 3.6 (RH 7.2 for IA64)
        elsif(/^\S+\s+([a-f0-9\:]{11,17}).*bootp/) {
            my $mac = mactransform($1);
            if(add_mac_to_hash($mac)) {
                regenerate_listbox($listbox);
            }
        }

        $window->update;
    }
    close(TCPDUMP);
    end_ping();
}

sub add_mac_to_hash {
    my $mac = shift;
    # if the mac is 00:00:00:00:00:00, it isn't real
    if($mac =~ /^[0\:]+$/) {
        return 0;
    }
    # if it already has an order, then we already know about it
    if($MAC{$mac}->{order}) {
        return 0;
    }
    # else, add the mac address with a null client
    $MAC{$mac} = {
                  client => undef,
                  order => $ORDER,
                 };
    $ORDER++;
    return 1;
}

# mac transform does a join map split trick to ensure that each octet is 2 characters

sub mactransform {
    my $mac = shift;
    my $return = join ':', (map {(length($_) == 1) ? "0$_" : "$_"} split (':',$mac));
    return $return;
}

# Sub to initiate the setup_pxe script
sub run_setup_pxe {
    my ($window) = @_;
    $window->Busy(-recurse => 1);
    print "Setting up network boot...\n";
    !system("./setup_pxe -v") or (carp($!), $window->Unbusy(), return undef);
    if ( -x "../packages/kernel/scripts/fix_network_boot" ) {
      system("../packages/kernel/scripts/fix_network_boot"); 
    }
    $window->Unbusy();
    return 1;
}


1;
