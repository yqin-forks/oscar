package WizardEnv;

# $Id$ 
# 
# Descr: Import any new system ENV additions/changes to the Wizard's ENV.
#
# Copyright (c) 2005 Oak Ridge National Laboratory.
#                    All rights reserved.
#
#
#  Notes:
#   N1) Ignore a few specific ENV Vars
#   N2) Only add/replace ENV, don't remove anything from existing ENV.
#   N3) Blindly update values for any existing ENV vars, sometime overwriting.
#   N4) Use '--login' to guarantee all profile related files are processed
#       and explicitly source the bashrc related files.  Otherwise,
#       only interactive shells get the bashrc related contents and in some
#       cases we'd remove things from the run-time ENV, e.g., PATH with
#       changed via bashrc files.
#
#--------------------------------------------------------------------

use IPC::Open2;
use Carp;
use warnings;
use strict;
use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(update_env);


my @PATHS= qw(/bin /usr/bin /sbin /usr/sbin);

 # bashrc files processed in order of occurance in array
my @BASHRC = ("/etc/bash.bashrc", "/etc/bashrc", "$ENV{HOME}/.bashrc");

my %ENV_IGNORE = (PWD=>1, OLDPWD=>1, SHLVL=>1, _=>1, USER=>1, USERNAME=>1,
                  LS_COLORS=>1, PS1=>1);

#   Input: n/a
#  Output: %ENV
#  Return: list of modified env items [possibly empty]
sub update_env
{
	my @modified_env = ();
	my $magicstr = "___MaGiCsTrInG-OSCAR::WizardEnv___";
	my ($bash_cmd, $echo_cmd, $env_cmd);

	croak "Error: 'bash' not found " 
	   if( not defined($bash_cmd = find_cmd("bash")) );

	croak "Error: 'echo' not found " 
	   if( not defined($echo_cmd = find_cmd("echo")) );

	croak "Error: 'env' not found " 
	   if( not defined($env_cmd = find_cmd("env")) );


	my ($rh, $wh);  # Handle autovivification 


	 # 1) Use the '--login' option in order to have profile related file 
	 #    sourced
	
	my $pid = open2($rh, $wh, "$bash_cmd", "--login") or croak "Error: $!\n";


	 # TODO: May need to trap SIGPIPE for child, see IPC::Open2(3pm)
	 #       when writing to the pipe (write handle).
	 #
	 # 2) We set PS1 to fake out some scripts that check for interactive
	 #    shells via this value being set, e.g., Debian's /etc/bash.bashrc
	 #    We have PS1 in %ENV_IGNORE so change won't propogate to cur ENV.
	 #
	 # 3) Then we manually source the bashrc related files (@BASHRC).
	 #    Note, we must check for existence, then source b/c naming differs.
	
	print $wh "export PS1=foobar\n";
	foreach my $rcfile (@BASHRC) {
		print $wh "if [ -e $rcfile ] ; then source $rcfile; fi\n";
	}

	 # 4) Print our delimiter, all output above this is from system,
	 #   e.g., /etc/profile.d/ssh-oscar.sh gens *lots* of output :-|
	 #
	 # TODO: May need to trap SIGPIPE for child, see IPC::Open2(3pm)
	 
	print $wh "/bin/echo $magicstr\n";

	 # 5) Get a listing of the new shell's ENV.
	 
	print $wh "$env_cmd";
	close($wh);

	 # 6) Drain the read pipe from shell and then do post-processing
	 #    to determine differences/additions to ENV and update cur ENV.
	 
	my @rslt = <$rh>;
	close($rh);
	chomp(@rslt);

	waitpid($pid, 0); # reap child (if needed?)


	 # Remove any leading stuffo (prior to our sentinal)
	while ( ($_ = shift(@rslt)) !~ /$magicstr/ ) {
		print "WizardEnv: removed($_)\n" if( $ENV{DEBUG_OSCAR_WIZARD_PARANOID});
		next;
	}
	print "WizardEnv: removed($_)\n\n" if( $ENV{DEBUG_OSCAR_WIZARD_PARANOID} );


	foreach my $r (@rslt) {
		my ($key, $val) = split/=/, $r;
    
		if( ! $ENV_IGNORE{$key} ) {

			next if( defined($ENV{$key}) && $ENV{$key} eq $val ); 
   
			print "Update environment: ENV{$key}\n" unless( $ENV{QUIET_OSCAR_WIZARD} );
			print "  $key=$val\n\n" if( $ENV{DEBUG_OSCAR_WIZARD} 
			                          && ! $ENV{QUIET_OSCAR_WIZARD} );

			# To see actual differential (for the paranoid among us)
   			if($ENV{DEBUG_OSCAR_WIZARD_PARANOID} && ! $ENV{QUIET_OSCAR_WIZARD}) 
			{
				# To avoid unintialized warnings when not prev. exist
				my $orig = (defined($ENV{$key}))? $ENV{$key} : ""; 
				print "  ORIG: $key=$orig\n";
				print "   NEW: $key=$val\n\n";
			}

			$ENV{$key} = $val;
			push @modified_env, $key;
		}
	}
	return @modified_env;
}


sub find_cmd 
{
	my $target = shift;
	my $cmd = undef;

	foreach my $path (@PATHS) {
		if( -x "$path/$target" ) {
			$cmd = $path . "/" . $target;
			last;
		}
	}

	return( ( defined($cmd) )?  $cmd : undef );
}

1;

# vim:tabstop=4:shiftwidth=4

