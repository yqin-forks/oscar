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
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
#
# Copyright (c) 2002 National Center for Supercomputing Applications (NCSA)
#                    All rights reserved.
#
# Written by Terrence G. Fleury (tfleury@ncsa.uiuc.edu)
#
# Copyright (c) 2002 The Trustees of Indiana University.  
#                    All rights reserved.
# 
# This file is part of the OSCAR software package.  For license
# information, see the LICENSE file in the top level directory of the
# OSCAR source distribution.
#
# $Id: Selector.pm,v 1.4 2002/10/29 19:11:37 tfleury Exp $
# 
##############################################################
#  MOVE THE STUFF BELOW TO THE TOP OF THE PERL SOURCE FILE!  #
##############################################################
package OSCAR::Selector;

use strict;
use vars qw(@EXPORT);
use base qw(Exporter);
our @EXPORT = qw(displayPackageSelector populateSelectorList deepcopy);

use lib "$ENV{OSCAR_HOME}/lib";
use Carp;
use OSCAR::Infobox;  # This is the pop-up information box
use OSCAR::Package;  # For list_pkg()
use OSCAR::Logger;   # For oscar_log_section()
use XML::Simple;     # Read/write the .selection config files
use Tk::Pane; 
use Tk::BrowseEntry;
use Tk::LabEntry;
use Tk::Dialog;
use Tk::DialogBox;

my($top);            # The Toplevel widget for the package selector window
my $step_number;     # Step number in the OSCAR wizard
##############################################################
#  MOVE THE STUFF ABOVE TO THE TOP OF THE PERL SOURCE FILE!  #
##############################################################
# Sample SpecTcl main program for testing GUI

use Tk;
require Tk::Menu;
#my($top) = MainWindow->new();
#$top->title("Selector test");


# interface generated by SpecTcl (Perl enabled) version 1.2 
# from Selector.ui
# For use with Tk402.002, using the grid geometry manager

sub Selector_ui {
	our($root) = @_;

	# widget creation 

	our($selectFrame) = $root->Frame (
	);
	my($frame_4) = $root->Frame (
		-borderwidth => '2',
		-relief => 'groove',
	);
	our($configSelectFrame) = $root->Frame (
	);
	my($label_1) = $root->Label (
		-font => '-*-Helvetica-Bold-R-Normal-*-*-140-*-*-*-*-*-*',
		-text => 'OSCAR Package Selection',
	);
	my($label_2) = $root->Label (
		-justify => 'left',
		-text => 'Configuration Name:',
	);
	my($newButton) = $root->Button (
		-font => '-*-Helvetica-Medium-R-Normal-*-*-100-*-*-*-*-*-*',
		-text => 'New',
	);
	my($renameButton) = $root->Button (
		-font => '-*-Helvetica-Medium-R-Normal-*-*-100-*-*-*-*-*-*',
		-text => 'Rename',
	);
	our($deleteButton) = $root->Button (
		-font => '-*-Helvetica-Medium-R-Normal-*-*-100-*-*-*-*-*-*',
		-state => 'disabled',
		-text => 'Delete',
	);
	my($exitNoSaveButton) = $root->Button (
		-default => 'active',
		-text => 'Exit without Saving',
	);
	my($saveAndExitButton) = $root->Button (
		-text => 'Save and Exit',
	);

	# widget commands

	$newButton->configure(
		-command => \&OSCAR::Selector::newConfig
	);
	$renameButton->configure(
		-command => \&OSCAR::Selector::renameConfig
	);
	$deleteButton->configure(
		-command => \&OSCAR::Selector::deleteConfig
	);
	$exitNoSaveButton->configure(
		-command => \&OSCAR::Selector::exitWithoutSaving
	);
	$saveAndExitButton->configure(
		-command => \&OSCAR::Selector::saveAndExit
	);

	# Geometry management

	$selectFrame->grid(
		-in => $root,
		-column => '1',
		-row => '3',
		-columnspan => '2',
		-sticky => 'nesw'
	);
	$frame_4->grid(
		-in => $root,
		-column => '1',
		-row => '2',
		-columnspan => '2',
		-sticky => 'nesw'
	);
	$configSelectFrame->grid(
		-in => $frame_4,
		-column => '1',
		-row => '2',
		-sticky => 'nesw'
	);
	$label_1->grid(
		-in => $root,
		-column => '1',
		-row => '1',
		-columnspan => '2',
		-sticky => 'ew'
	);
	$label_2->grid(
		-in => $frame_4,
		-column => '1',
		-row => '1',
		-sticky => 'ew'
	);
	$newButton->grid(
		-in => $frame_4,
		-column => '2',
		-row => '1',
		-sticky => 'ew'
	);
	$renameButton->grid(
		-in => $frame_4,
		-column => '3',
		-row => '1',
		-sticky => 'ew'
	);
	$deleteButton->grid(
		-in => $frame_4,
		-column => '2',
		-row => '2',
		-columnspan => '2',
		-sticky => 'ew'
	);
	$exitNoSaveButton->grid(
		-in => $root,
		-column => '1',
		-row => '4',
		-sticky => 'ew'
	);
	$saveAndExitButton->grid(
		-in => $root,
		-column => '2',
		-row => '4',
		-sticky => 'ew'
	);

	# Resize behavior management

	# container $frame_4 (rows)
	$frame_4->gridRowconfigure(1, -weight  => 0, -minsize  => 2);
	$frame_4->gridRowconfigure(2, -weight  => 0, -minsize  => 2);

	# container $frame_4 (columns)
	$frame_4->gridColumnconfigure(1, -weight => 1, -minsize => 106);
	$frame_4->gridColumnconfigure(2, -weight => 0, -minsize => 38);
	$frame_4->gridColumnconfigure(3, -weight => 0, -minsize => 2);

	# container $root (rows)
	$root->gridRowconfigure(1, -weight  => 0, -minsize  => 30);
	$root->gridRowconfigure(2, -weight  => 0, -minsize  => 2);
	$root->gridRowconfigure(3, -weight  => 1, -minsize  => 200);
	$root->gridRowconfigure(4, -weight  => 0, -minsize  => 30);

	# container $root (columns)
	$root->gridColumnconfigure(1, -weight => 1, -minsize => 168);
	$root->gridColumnconfigure(2, -weight => 1, -minsize => 86);

	# additional interface code

our($packagexml);             # Holds the XML configs for each package
our(@packagedirs);            # A list of valid OSCAR package directories
our($oscarbasedir);           # Where the program is called from
our($pane);                   # The pane holding the scrolling selection list
our($configselect);           # The Optionmenu widget for Configuration Name
our($configselectstring);     # The current selection of the Optionmenu
our($selconf); 
our(%packagecheckbuttons);

#########################################################################
#  Called when the "Exit without Saving" button is pressed.             #
#########################################################################
sub exitWithoutSaving
{
  # If the $root window has a Parent, then it isn't a MainWindow, which
  # means that another MainWindow is managing the OSCAR Package Selection
  # window.  Therefore, when we exit, unmap the window.  If there is
  # no parent, then it IS a MainWindow, so destroy the window.
  $root->Parent ? $root->UnmapWindow : $root->destroy;

  # If there are any children, make sure they are unmapped.
  my (@kids) = $root->children;
  foreach my $kid (@kids)
    {
      $kid->UnmapWindow;
    }

  # Write out a message to the OSCAR log
  oscar_log_subsection("Step $step_number: Completed successfully");
}

#########################################################################
#  Called when the "Save and Exit" button is pressed.                   #
#########################################################################
sub saveAndExit
{
  writeOutSelectionConfig();
  exitWithoutSaving();
}

#########################################################################
#  Subroutine: deepcopy                                                 #
#  Parameter : A reference (hash or array) to copy                      # 
#  Returns   : A copy of the passed in reference (hash or array)        #
#  This subroutine is a general function to do a "deep copy" of a       #
#  data structure.  A normal "shallow copy" only copies the elements of #
#  a hash/array at the current level.  Any hashes/arrays at lower       #
#  levels don't get copied.  A "deep copy" recurses down the tree and   #
#  copies all levels.  This subroutine was taken from Unix Review       #
#  Column 30, February 2000.                                            #
#########################################################################
sub deepcopy # ($array_hash) -> $array_hash_copy
{
  my $this = shift;
  if (not ref $this) 
    { $this; } 
  elsif (ref $this eq "ARRAY")
    { [map deepcopy($_), @$this]; } 
  elsif (ref $this eq "HASH") 
    { +{map { $_ => deepcopy($this->{$_}) } keys %$this}; }
  else 
    { die "what type is $_?" }
}

#########################################################################
#  Subroutine: fixCheckButtons                                          #
#  Parameters: None                                                     #
#  Returns   : Nothing                                                  #
#  This subroutine is called whenever a configuration name is selected, #
#  created, renamed, or deleted.   The checkbuttons on the selector     #
#  are tied to variables.  These variables change for each selected     #
#  configuration.  So, when a different configuration is selected, we   #
#  need to remap the checkbuttons to the appropriate variables.  Also,  #
#  we need to turn on/off the checkbuttons for the newly selected       #
#  configuration.                                                       #
#########################################################################
sub fixCheckButtons
{
  foreach my $package (sort keys %{ $packagexml } )
    { # First, remap the checkbuttons to variables for the new configuration
      $packagecheckbuttons{$package}->configure(-variable =>
        \$selconf->{configs}{$configselectstring}{packages}{$package});
      # Then, turn on/off the checkbuttons for the new configuration
      if ($selconf->{configs}{$configselectstring}{packages}{$package})
        {
          $packagecheckbuttons{$package}->select;
        }
      else
        {
          $packagecheckbuttons{$package}->deselect;
        }
    }
}

#########################################################################
#  Subroutine: configDialog                                             #
#  Parameter : Run in "Rename" mode (true) or "New" mode (false).       #
#  Returns   : nothing                                                  #
#  This subroutine is called by renameConfig and newConfig to pop up    #
#  a dialog box to prompt the user for a new name of a Configuration.   #
#  If you pass in "1" to the subroutine, it pops up the "Rename         #
#  Configuration" dialog box.  Otherwise, it pops up the "New           #
#  Configuration" dialog box.                                           #
#########################################################################
sub configDialog
{
  my ($rename) = @_;     # Pop up "Rename" (1) or "New" (0) dialog box

  my $newname;           # The new name typed in by the user
  my $db;                # The DialogBox widget
  my $answer;            # Which button was pressed by the user?
  my $success = 0;       # Was there an error during the process?
  my $errorstring = "";  # The string to output if there was an error

  # Continue popping up DialogBoxes until there is no user error
  do
    {
      $newname = "";
      # Create a DialogBox with the appropriate title (Rename/New)
      $db = $root->DialogBox(
        -title => (($rename ? 'Rename' : 'New') . ' Configuration'), 
        -buttons => ['Ok','Cancel'],
        # -default_button => 'Cancel',
      );

      # Add a label for the error (if there was an error)
      $db->add("Label", 
               -text => $errorstring,
               -foreground => '#aa0000',
              )->pack(-anchor => 'w') if ($errorstring);
      # Add a label for what the user should enter
      $db->add("Label", 
               -text => ($rename ? 
                        "Rename configuration '$configselectstring' to:" : 
                        "Enter a name for the new configuration."),
              )->pack(-anchor => 'w');
      # Add a labeled text entry box for the user to type in
      $db->add("LabEntry", 
               -textvariable => \$newname,
               -width => 30,
               -label => 'New name:',
               -labelPack => [-side => 'left'],
              )->pack(-anchor => 'w');
      $answer = $db->Show();

      if ($answer eq 'Ok') 
        { 
          if (length($newname) <= 0)
            { # Check to see if the user entered anything at all
              $errorstring = "The new name cannot be empty.";
            }
          elsif ($rename && ($newname eq $configselectstring))
            { # Make sure the new name differs from the current name
              $errorstring = "You must enter a new name.";
            }
          elsif ($selconf->{configs}{$newname})
            { # Make sure the new name isn't already taken
              $errorstring = "The name '$newname' already exists.";
            }
          else
            { # Success! Delete the name (if rename) and add a new name
              $selconf->{configs}{$newname} = 
                deepcopy($selconf->{configs}{$configselectstring});
              delete $selconf->{configs}{$configselectstring} if $rename;
              $configselectstring = $newname;
              $success = 1;
              # Recreate the Optionmenu widget
              createConfigSelect();
              # Remap the checkbuttons to the new configuration's variables
              fixCheckButtons();
            }
        }
      else # Answer was "Cancel", so do nothing - all done
        { 
          $success = 1;
        }
    } until ($success);
}

#########################################################################
#  Called when the "Rename" button is pressed.  It pops up the          #
#  New/Rename Configuration dialog box (in "Rename" mode).              #
#########################################################################
sub renameConfig
{
  configDialog(1);
}

#########################################################################
#  Called when the "New" button is pressed.  It pops up the             #
#  New/Rename Configuration dialog box (in "New" mode) and then sets    #
#  the "Delete" button to active if we successfully added a new item.   #
#########################################################################
sub newConfig
{
  configDialog();
  $deleteButton->configure(-state => 'active') if 
    (scalar (keys %{ $selconf->{configs} }) > 1);
}

#########################################################################
#  Called when the "Delete" button is pressed.  It first makes sure     #
#  that there are at least 2 items in the Optionmenu (so that there     #
#  is 1 left after deleting) and then prompts the user to confirm the   #
#  deletion.                                                            #
#########################################################################
sub deleteConfig
{
  # Make sure we have at least 2 items in the list
  return if (scalar (keys %{ $selconf->{configs} }) <= 1);

  # Create a dialog box to prompt for delete confirmation
  my $answer = $root->Dialog(
    -title => "Confirm Delete",
    -buttons => [ 'Yes', 'No' ],
    -default_button => 'No',
    -text => "Delete configuration named '$configselectstring'?",
  )->Show();

  if ($answer eq 'Yes')
    {
      # Remove the item from the hash
      delete $selconf->{configs}{$configselectstring};
      # Set the newly displayed Optionmenu item to the first in the list
      $configselectstring = 
        (sort { lc($a) cmp lc($b) } keys %{ $selconf->{configs} })[0];
      # Update the Optionmenu widget
      createConfigSelect();
      # Disable the button if only one item left in the list
      $deleteButton->configure(-state => 'disabled') if 
        (scalar (keys %{ $selconf->{configs} }) <= 1);
    }
}

#########################################################################
#  Subroutine name : readInPackageXMLs                                  #
#  Parameters: None                                                     #
#  Returns   : Nothing                                                  #
#  This function reads through the list of OSCAR "package" directories  #
#  and checks for a file named ".selection".  If this file is found,    #
#  it is parsed for various options which are stored in the global      #
#  hash variable $packagexml.  This hash is indexed by the names of     #
#  the OSCAR package directories.                                       #
#########################################################################
sub readInPackageXMLs
{
  $packagexml = pkg_config_xml();

  # Make sure that there is at least a "name" for all packages
  foreach my $package (@packagedirs)
    { 
      $packagexml->{$package}{name} = $package if 
        ((!$packagexml) || (!$packagexml->{$package}) || 
         (!$packagexml->{$package}{name}));
    }
}

#########################################################################
#  Subroutine : setSelectionConfigDefaults                              #
#  Parameters : None                                                    #
#  Returns    : Nothing                                                 #
#  This subroutine sets the default values for the .selection.config    #
#  file if that file is corrupt or non-existant.  Right now, all of     #
#  the OSCAR packages are installed by default.                         #
#########################################################################
sub setSelectionConfigDefaults
{
  $configselectstring = 'Default';
  $selconf->{selected} = $configselectstring;
  foreach my $package (sort keys %{ $packagexml } )
    {
      $selconf->{configs}{$configselectstring}{packages}{$package} = 1;
    }
}

#########################################################################
#  Subroutine name : readInSelectionConfigs                             #
#  Parameters: None                                                     #
#  Returns   : Nothing                                                  #
#  This function reads in the XML file named .selection.config located  #
#  under the OSCAR installation directory.  The values are stored in    #
#  the hash named "%selconf".                                           #
#########################################################################
sub readInSelectionConfig
{
  my($writeconfig) = 0;  # Do we write out a new default config file?
  my($config) = "$oscarbasedir/.oscar/.selection.config";

  if (-s $config)    # Does the file exist?
    {
      $selconf = eval { XMLin($config,suppressempty => ''); };
      if ($@)   
        { # Whoops! Error. Write out a new default config file.
          carp("Warning! The .selection.config file was invalid. Writing a new default file...");
          setSelectionConfigDefaults();
          $writeconfig = 1;
        }
      else
        { # Successful read. Set the Selected Config and enable Delete button
          $configselectstring = $selconf->{selected};
          $deleteButton->configure(-state => 'active') if 
            (scalar (keys %{ $selconf->{configs} }) > 1);
        }
    }
  else  # Couldn't find config file.  Set defaults.
    {
      setSelectionConfigDefaults();
    }

  # If there was an incorrect or missing config file, write out a new one.
  writeOutSelectionConfig() if ($writeconfig);
}

#########################################################################
#  Subroutine: writeOutSelectionConfig                                  #
#  Parameters: None                                                     #
#  Returns   : Nothing                                                  #
#  This subroutine writes out the configuration names (and the name     #
#  of the configuration currently selected) to an XML file.             #
#########################################################################
sub writeOutSelectionConfig 
{
  system("mkdir -p $oscarbasedir/.oscar");
  $selconf->{selected} = $configselectstring;
  XMLout($selconf,
         outputfile => "$oscarbasedir/.oscar/.selection.config",
         noescape => 1,
         rootname => 'selection',
         noattr => 1,
         keyattr => [],
        );
}

#########################################################################
#  This subroutine is called when one of the checkbuttons in the        #
#  package listing is clicked.  Right now, all it does is enable the    #
#  "Save and Exit" button.                                              #
#########################################################################
#sub checkButtonSelected
#{
#  $saveAndExitButton->configure(-state => 'active');
#}

#########################################################################
#  Subroutine : populateSelectorList                                    #
#  Parameters : None                                                    #
#  Returns    : Nothing                                                 #
#  This subroutine is the main function for the "Oscar Package          #
#  Selector".  It fills in the main window with a scrolling list of     #
#  OSCAR packages allowing the user to enable/disable each package,     #
#  view helpful information about the package (if any), and configure   #
#  the package (if enabled).  It creates a scrolling pane and populates #
#  it with the list of package directories found under the main OSCAR   #
#  directory.                                                           #
#########################################################################
sub populateSelectorList
{
  my($tempframe);

  # Set up the base directory where this script is being run
  $oscarbasedir = '.';
  $oscarbasedir = $ENV{OSCAR_HOME} if ($ENV{OSCAR_HOME});
  @packagedirs = list_pkg();  # Scan for directories under "packages"
  readInPackageXMLs();        # Read in all packages' config.xml files
  readInSelectionConfig();

  $pane->destroy if ($pane);
  # First, put a "Pane" widget in the center frame
  $pane = $selectFrame->Scrolled('Pane', -scrollbars => 'osoe');
  $pane->pack(-expand => '1', -fill => 'both');

  # Now, start adding OSCAR package stuff to the pane
  if (scalar(@packagedirs) == 0)
    {
      $pane->Label(-text => "Couldn't find any OSCAR packages.")->pack;
    }
  else
    { # Create a temp Frame widget for each package row
      my $pkgxml = pkg_config_xml();
      foreach my $package (sort keys %{ $packagexml } )
        {
          $tempframe = $pane->Frame()->pack(-side => 'top',
                                            -fill => 'x',
                                           );
          # Then add the checkbutton, info/config buttons, and package name
          # First, the checkbutton
          $packagecheckbuttons{$package} = $tempframe->Checkbutton(
            -state => (((defined $pkgxml->{$package}{class}) &&
                       ($pkgxml->{$package}{class} eq 'core')) ?
                       'disabled' : 'normal'),
            -variable =>
              \$selconf->{configs}{$configselectstring}{packages}{$package},
            # -command => \&checkButtonSelected,
          )->pack(-side => 'left');
          $packagecheckbuttons{$package}->select if 
            $selconf->{configs}{$configselectstring}{packages}{$package};

          # Then, the Info button
          $tempframe->Button(
            -text => 'Info',
            -command => [ \&OSCAR::Infobox::displayInformation , 
                          $root,
                          $packagexml->{$package}{name},
                          $packagexml->{$package}{description}
                        ],
            -state => (($packagexml->{$package}{description} =~ /^\s*$/) ? 
                      'disabled' : 'normal'),
            )->pack(-side => 'left');

          # Finally, the package name label
          $tempframe->Label(
            -text => $packagexml->{$package}{name},
            )->pack(-side => 'left');
        }
    }
}

#########################################################################
#  Subroutine: createConfigSelect                                       #
#  Parameters: None                                                     #
#  Returns   : Nothing                                                  #
#  This subroutine creates (and recreates) the Optionmenu which lists   #
#  the names of the various configurations available to the user.       #
#  The option selected in the list is stored in the variable            #
#  $configselectstring.                                                 #
#########################################################################
sub createConfigSelect
{
  my $selectedstring = $configselectstring;

  $configselect->destroy if ($configselect);
  # Put an Optionmenu widget in the configselect frame
  $configselect = $configSelectFrame->Optionmenu(
                   -textvariable => \$configselectstring,
                   -command => \&fixCheckButtons,
                 );
  foreach my $string (sort { lc($a) cmp lc($b) } keys %{ $selconf->{configs} })
    {
      $configselect->addOptions($string);
    }
  $configselect->setOption($selectedstring);
  $configselect->pack(-expand => '1', -fill => 'both');
}

#########################################################################
#  Subroutine : displayPackageSelector                                  #
#  Parameter  : The parent widget which manages the selector window     #
#  Returns    : Nothing                                                 #
#  This is the main subroutine of the Selector.  It is called either    #
#  in the main program (if the Selector is running alone) or by another #
#  top-level window (if the Selector is running as a Perl module).      #
#  It creates and populates the Selector window.                        #
#########################################################################
sub displayPackageSelector # ($parent)
{
  my $parent = shift;
  $step_number = shift;  

  # Check to see if our toplevel selector window has been created yet.
  if (!$top)
    { # Create the toplevel window just once
      if ($parent)
        {
          $top = $parent->Toplevel(-title => 'Oscar Package Selection',
                                   -width => '260',
                                   -height => '260',
                                  );
        }
      else 
        { # If no parent, then create a MainWindow at the top.
          $top = MainWindow->new();
          $top->title("Oscar Package Selection");
        }
      OSCAR::Selector::Selector_ui $top;  # Call the specPerl window creator
    }

  # Then create the scrollable package listing and place it in the grid.
  populateSelectorList();
  # Create the Optionmenu widget for the configuration name.
  createConfigSelect();
  oscar_log_section("Running step $step_number of the OSCAR wizard: Select OSCAR packages to install");
  $root->MapWindow;   # Put the window on the screen.
}

############################################
#  Set up the contents of the main window  #
############################################

#displayPackageSelector($top);


	# end additional interface code
}
#Selector_ui $top;
#Tk::MainLoop;

1;
