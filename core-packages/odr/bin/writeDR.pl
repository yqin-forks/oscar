#!/usr/bin/perl

#   $Header: /home/user5/oscar-cvsroot/oscar/core-packages/odr/bin/Attic/writeDR.pl,v 1.1 2001/08/14 20:01:58 geiselha Exp $

#   Copyright (c) 2001 International Business Machines

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

#   Greg Geiselhart <geiselha@us.ibm.com>

# write - add/modify ODR information

use strict;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use clamdr::API;
use Getopt::Long;
use Data::Dumper;
$Getopt::Long::ignorecase = 0;

my $defsyn = 'oscar';

sub usage {
    my $progname = $0;
    if ($progname =~ m/(.+\/)(\w+)/) {
	$progname = $2;
    }
    print <<USAGE;
usage: $progname [ options ] filename <column specification>
  options
    -D, --Directory
       Directory for data files (default: $Test::API::DATADIR)
    -s, --syntax
       Syntax to use (default: $defsyn)
    -F, --Force
       Force deletion/update
    -a, --add
       Adds a row to file ( set to values specified in <columns> )
    -d, --delete
       Delete row(s) from file
    -f, --filter < filter specification >
       Specifies filter criteria applied to update
  filename
    name of the file on which to operate
  <column spec>
    list of NAME=VALUE pairs ( NAME=column name, VALUE=value to assign )
  <filter spec>
    list of NAME=VALUE pairs ( NAME=column name, VALUE=value to filter on )
    may be specified as N1=v1,N2=v2 or -f N1=V1 -f N2=V2
    filter specs are logically ANDed

if neither --add nor --delete is provided, operation is assumed to be update

USAGE
    exit 1;
}

#
# parses a string into 2 parts delimited by ','
#
sub parse {
    my $str = shift;
    return split /,/, $str;
}

sub thisExists {
    my ($category, %keys) = @_;
    my ($c, $v, @cols, @vals);
    while (($c, $v) = each(%keys)) {
	push @cols, $c;
	push @vals, $v;
    }
    my $sql = "SELECT " . (join ',', @cols) . " FROM $category WHERE ";
    $sql .= join " AND ", map { "$_=?"} @cols;
    my $sth = $DBH->prepare($sql);
    my $found = 0;
    $sth->execute(@vals);
    $found = 1 if $sth->fetchrow_arrayref;
    $sth->finish;
    return $found;
}

my %options;
GetOptions(\%options,
	   "delete",
	   "add",
	   "filter|f=s@",
	   "Directory=s",
	   "syntax=s",
	   "Force",
	  );
my ($category, @values) = @ARGV;

my $syn = $options{syntax} || $defsyn;
my $syntax = initialize($syn);

if ($options{Directory}) {
    if (not -d $options{Directory}) {
	print "$options{Directory} not a directory\n";
	usage;
    }
    if (not -r $options{Directory}) {
	print "$options{Directory} not readable\n";
	usage;
    }
    if (not -f "$options{Directory}/syntax") {
	print "$options{Directory} has no syntax\n";
	usage;
    }
}

usage unless $category;
if ($options{add} and $options{delete}) {
    print "options add and delete are mutually exclusive\n";
    usage;
}

if (not $syntax->valid_category($category)) {
    print "$category is a not recognized category\n";
    usage;
}

my (%filters, %columns);

#
# check validity of all options values
#
foreach my $opt (@{$options{filter}}) {
    $opt =~ s/\s//g;
    my @params = parse($opt);
    foreach (@params) {
	if (m/(.+)=(.+)/) {
	    my ($name, $value) = ($1, $2);
	    if (not $syntax->valid_tag($category, $name)) {
		print "$name is not a recognized tag\n";
		usage;
	    }
	    $filters{$name} = $value;
	} else {
	    print "filters must be specified and name=value pairs\n";
	    usage;
	}
    }
}

#
# check validity of all positional parameters
#
foreach (@values) {
    s/\s//g;
    if (m/(.+)=(.+)/) {
	my ($name, $value) = ($1, $2);
	if (not $syntax->valid_tag($category, $name)) {
	    print "$name is not a recognized tag\n";
	    usage;
	}
	$columns{$name} = $value;
    } else {
	if (m/(.+)=$/) {
	    $columns{$1} = '';
	} else {
	    print "columns must be specified and name=value pairs\n";
	    usage;
	}
    }
}

my @cols = keys %columns;
my @vals = values %columns;
my @filts = keys %filters;
my @fvals = values %filters;

if ($options{add}) { # add requested
    my ($valid, %keys) = (1, ());
    foreach (@{$syntax->{$category}->{keys}}) {
	if (not defined($columns{$_})) {
	    $valid = 0;
	    last;
	}
	$keys{$_} = $columns{$_};
    }
    if (not $valid) {
	print "all key values [ " .
	  (join ',', map { "$_"} @{$syntax->{$category}->{keys}} ) .
	    " ] must be specified for add\n";
	exit 1;
    }
    if (thisExists($category, %keys)) {
	print "$category: [ " . 
	  (join ',', map { "$_=$keys{$_}"} keys %keys) .
	    " ] already exists -- not added\n";
	$valid = 0;
    }
    exit 1 unless $valid;
    my $sql = "INSERT INTO $category (" .
      (join ',', @cols) . ") VALUES (" .
	(join ',', map { "?" } @cols) . ")";
    my $sth = $DBH->prepare($sql);
    $sth->execute(@vals);
    exit 0;
}

if ($options{delete}) { # delete requested
    @filts = (@filts, @cols);
    @fvals = (@fvals, @vals);
    my $sql = "DELETE FROM $category";
    if (scalar(@filts)) {
 	$sql .= " WHERE " . (join ' AND ', map { "$_=?" } @filts);
    } else {
	if (not $options{Force}) {
	    print "all $category rows would be deleted. Specify --Force to force the issue\n";
	    exit 1;
	}
    }
    my $sth = $DBH->prepare($sql);
    $sth->execute(@fvals);
    exit 0;
}

# default is update....

if (not scalar(@cols)) { # makes no sense unless new values are supplied
    print "updates must specify new values\n";
    usage;
}

# build SQL
my $sql = "UPDATE $category SET " . (join ',', map { "$_=?" } @cols);
if (scalar(@filts)) { # add WHERE if filtering
    $sql .= " WHERE " . (join ' AND ', map { "$_=?" } @filts);
} else {
    if (not $options{Force}) {
	print "all $category rows would be updated. Specify --Force to force the issue\n";
	exit 1;
    }
    foreach (@{$syntax->{$category}->{keys}}) {
	if (defined($columns{$_})) {
	    print "cannot apply unfiltered update on key values (even with --Force)\n";
	    exit 1;
	}
    }
}
foreach (@{$syntax->{$category}->{keys}}) {
    if (defined($columns{$_}) and not $options{Force}) {	
	print "updating on a key value, be careful! Specify --Force to force the issue\n";
	exit 1;
    }
}

# execute it....
my $sth = $DBH->prepare($sql);
$sth->execute(@vals, @fvals);
exit 0;

__END__

=head1 NAME

writeDR - script to add, update, delete CLAMDR data

=head1 SYNOPSIS

  writeDR --add client NAME=node1 DEFAULT_ROUTE=10.0.0.1 # add a client
  writeDR -f NAME=node1 client STATE=enabled # update client 'node1'
  writeDR -d client STATE=disabled # delete all clients with STATE=disabled

=head1 DESCRIPTION

B<writeDR> is a command line interface to write cluster persistent data.
Parameters are read from the command line and are changes applied to the
persistent data.

=head2 Syntax

writeDR [I<options>] filename [I<column spec>]

=head2 Options

The following options are recognized:

=over 4

=item -D, --Directory

Directory where data files are located.

=item -F, --Force

Force delete/update

=item -a, --add

Add row to data file.

=item -d, --delete

Delete row from data file.

=item -f, --filter=I<filer spec>

Filter specification

=item -s, --syntax

Syntax to apply when reading data files.

=back

=head2 Filename

The name of the data file to write. A complete list of all defined data files may
be obtained by issuing the command:

readDR --list

=head2 Column spec

Column specification consists of whitespace delimited I<NAME=VALUE> pairs
used to assign values during B<add> or B<update> operation. Column names
not provided for an B<add> operation will be assigned an undefined value.
Column names not provided for an B<update> operation will be not be changed.
Column spec is ignored for B<delete> operation.

=head2 Filter spec

Filter specification consists of I<NAME=VALUE> pairs specified on the B<--filter> option.
Multiple <--filter> options may be provided as in:

-f A=2 --filter='B=3'

or filters may be grouped using a ',' delimiter, as in:

--filter='A=2,B=3'

The complete filter specification is the logically B<and> of all filter clauses. Note
that the filter specification is an exact match only test.

Be aware that in the event no filter spec is provided for an B<update> or a B<delete>
operation, all rows will be affected. In this situation, the B<--Force> option must
be supplied to coerce operation (this is strictly a safety measure to prevent
inadvertent data modification).

=head1 AUTHOR

Greg Geiselhart, geiselha@us.ibm.com

=head1 SEE ALSO

perl(1), readDR(1).

=cut
