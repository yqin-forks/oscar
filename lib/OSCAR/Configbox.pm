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
##############################################################
#  MOVE THE STUFF BELOW TO THE TOP OF THE PERL SOURCE FILE!  #
##############################################################
package OSCAR::Configbox;

use strict;
use base qw(Exporter);
our @EXPORT = qw(configurePackage exitWithoutSaving readInConfigValues);
require Tk::Web;
require URI::URL;
use Carp;
use HTML::TreeBuilder 3;
use XML::Simple;      
no warnings qw(closure);
use OSCAR::Tk;

my($top);            # The Toplevel widget for the config box.
my($web);            # The Tk::Web widget for displaying HTML file.
my($packagedir);
##############################################################
#  MOVE THE STUFF ABOVE TO THE TOP OF THE PERL SOURCE FILE!  #
##############################################################

# Sample SpecTcl main program for testing GUI

use Tk;
require Tk::Menu;
#my($top) = MainWindow->new();
#$top->title("OSCAR::Configbox test");


# interface generated by SpecTcl (Perl enabled) version 1.2 
# from OSCAR::Configbox.ui
# For use with Tk402.002, using the grid geometry manager

sub Configbox_ui {
	our($root) = @_;

	# widget creation 

	our($configFrame) = $root->Frame (
	);
	our($configLabel) = $root->Label (
		-font => '-*-Helvetica-Bold-R-Normal-*-*-120-*-*-*-*-*-*',
		-text => 'Configuration',
	);
	my($defaultConfigurationButton) = $root->Button (
		-font => '-*-Helvetica-Bold-R-Normal-*-*-120-*-*-*-*-*-*',
		-text => 'Default Configuration',
	);
	my($cancelButton) = $root->Button (
		-default => 'active',
		-text => 'Cancel',
	);
	our($saveButton) = $root->Button (
		-state => 'disabled',
		-text => 'Save',
	);

	# widget commands

	$defaultConfigurationButton->configure(
		-command => \&OSCAR::Configbox::defaultConfiguration
	);
	$cancelButton->configure(
		-command => \&OSCAR::Configbox::exitWithoutSaving
	);
	$saveButton->configure(
		-command => \&OSCAR::Configbox::saveAndExit
	);

	# Geometry management

	$configLabel->grid(
		-in => $root,
		-column => 0,
		-row => 0,
		-columnspan => '3',
		-sticky => 'ew'
	);
	$configFrame->grid(
		-in => $root,
		-column => 0,
		-row => 1,
		-columnspan => '3',
		-sticky => 'nesw'
	);
	$defaultConfigurationButton->grid(
		-in => $root,
		-column => 0,
		-row => 2,
		-sticky => 'ew'
	);
	$cancelButton->grid(
		-in => $root,
		-column => 1,
		-row => 2,
		-sticky => 'ew'
	);
	$saveButton->grid(
		-in => $root,
		-column => 2,
		-row => 2,
		-sticky => 'ew'
	);

	# Resize behavior management

	# container $root (rows)
	$root->gridRowconfigure(0, -weight  => 0, -minsize  => 30);
	$root->gridRowconfigure(1, -weight  => 1, -minsize  => 200);
	$root->gridRowconfigure(2, -weight  => 0, -minsize  => 30);

	# container $root (columns)
	$root->gridColumnconfigure(0, -weight => 1, -minsize => 128);
	$root->gridColumnconfigure(1, -weight => 1, -minsize => 130);
	$root->gridColumnconfigure(2, -weight => 1, -minsize => 2);

	# additional interface code

#########################################################################
#  Called when the "Default Configuration" button is pressed.           #
#########################################################################
sub defaultConfiguration
{
  # Read in the non-modified HTML config file.  We do this instead of simply
  # copying the configurator.html file to .configurator.temp.html because the
  # readInDefaultConfig subroutine removes some offensive HTML tags for us.
  my($tree) = readInDefaultConfig("$packagedir/configurator.html");
  # Delete the .configurator.values modification file.
  # system("rm -f $packagedir/.configurator.values");
  # Write out the temporary .configurator.temp.html file.
  writeOutTempConfig($tree);
  $tree->delete;  # Always delete the tree when you are done with it.

  # Hide the window so that selection boxes draw correctly
  $web->UnmapWindow;
  # Set the 'Save' button to active
  $saveButton->configure(-state => 'active');
  loadHTMLFile("$packagedir/.configurator.temp.html");
  # loadHTMLFile("$packagedir/test.html");
}

#########################################################################
#  Called when the "Cancel" button is pressed.                          #
#########################################################################
sub exitWithoutSaving
{
  if ($root)
    {
      # If there are any children, make sure they are destroyed.
      my (@kids) = $root->children;
      foreach my $kid (@kids)
        {
          $kid->destroy;
        }

      # Then, destroy the root window.
      $root->destroy;

      # Undefine a bunch of Tk widget variables for re-creation later.
      undef $root;
      undef $top;
      undef $web;
    }
}

#########################################################################
#  Called when the "Save" button is pressed.                            #
#########################################################################
sub saveAndExit
{
  # Save the current configuration to the .configurator.values file.
  writeOutConfigValues();
  exitWithoutSaving();
}

#########################################################################
#  Subroutine: readInDefaultConfig                                      #
#  Parameter : The name of the HTML file to read in.                    #
#  Returns   : The HTML::Tree generated from the input HTML file.       #
#  This subroutine reads in an HTML file and generates a tree which     #
#  gets returned.  Along the way, it removes a few offensive HTML tags  #
#  which the current renderer doesn't handle well.                      #
#########################################################################
sub readInDefaultConfig # ($filename) -> $tree
{
  my($filename) = @_;

  my($tree) = HTML::TreeBuilder->new;
  $tree->ignore_ignorable_whitespace(0);  # Keep all whitespace intact
  $tree->no_space_compacting(0);          # Allow multiple contiguous spaces
  $tree->store_comments(1);               # Keep comments in tree
  my($success) = $tree->parse_file($filename);

  if ($success)
    { # Remove several offending HTML tags.
      foreach my $d ($tree->look_down(
        sub 
          {
            return 1 if ($_[0]->tag eq 'isindex');  # No searchable indicies
            return 1 if ($_[0]->tag eq 'a');        # Don't allow hyperlinks
            if ($_[0]->tag eq 'input')              # Not these 4 INPUT tags
              {
                my $type = $_[0]->attr('type');
                return 1 if ((defined $type) && 
                             (($type eq 'button') || ($type eq 'file') ||
                              ($type eq 'image') || ($type eq 'submit')));
              }
            return 0;
          } ))
        {
          $d->delete;
        }
    }
  else
    {
      undef $tree;
    }
 
  return $tree;
}

#########################################################################
#  Subroutine: readInConfigValues                                       #
#  Parameter : The name of the simple XML config file to read in.       #
#  Returns   : A HASH containing all of the XML tags and their values.  #
#  This subroutine takes the name of a file and reads it as if it was   #
#  a simple configuration file suitable for XML::Simple.  It returns    #
#  a reference to a HASH containing the key/value pairs.  Note that     #
#  the values are actually ARRAYS, so you must either iterate through   #
#  each hash entry, or assume that there is but a single element in the #
#  array and thus access the 0th element.                               #
#########################################################################
sub readInConfigValues # ($filename) -> $values
{
  my($filename) = @_;

  my($values) = eval
    { XMLin($filename, suppressempty => '', forcearray => '1'); };
  undef $values if ($@);

  return $values;
}

#########################################################################
#  Subroutine: preprocessConfig                                         #
#  Parameters: 1. The HTML tree generated by readInDefaultConfig.       #
#              2. A values HASH generated by readInConfigValues.        #
#  Returns   : Nothing.                                                 #
#  Once you have called the above two subroutines, you want to somehow  #
#  combine them.  The $tree represents the original HTML configuration  #
#  file which is not modified by this program.  The $values HASH        #
#  reference contains "modifications" to the $tree, which were set      #
#  by the user on a previous execution of this code.  This subroutine   #
#  iterates through both the $tree and the $values to make the $tree    #
#  reflect the information in the $values.  There's several steps       #
#  involved, so please see the comments in the subroutine.              #
#########################################################################
sub preprocessConfig # ($tree,$values)
{
  my($tree,$values) = @_;

  # Step 1: Scan through all "input" tags which are "checked" and see 
  #         if that name exists in $values.  If not, then clear the
  #         "checked" status.  
  foreach my $d ($tree->look_down(
    sub 
      {
        return 1 if (($_[0]->tag eq 'input') && ($_[0]->attr('checked')));
        return 0;
      } ))
    {
      $d->attr('checked',undef) if 
        ($d->attr('value') ne $values->{$d->attr('name')}[0]);
    }

  # Step 2: Search for "select" tags and make all of their subtree "option"
  #         tags not 'selected'.  We will reselect them in Step 3(c).
  foreach my $d ($tree->look_down(
    sub 
      {
        return 1 if ($_[0]->tag() eq 'select');
        return 0;
      } ))
    {
      # SELECT tag has OPTION tags as its children.
      my @kids = $d->content_list();
      foreach my $kid (@kids)
        {
          next if (!ref $kid);  # Ignore any text elements
          $kid->attr('selected',undef) if ($kid->tag() eq 'option');
        }
    }


  # Step 3: Scan through all the values and search the tree for a node with
  #         the same name.  Then make sure that value agrees with the node 
  #         in the tree.  We have four things to worry about:
  #         (a) if "type" is "checkbox", then set the "checked" status.
  #         (b) if "type" is "radio", check for a node in the tree named
  #             that value and set its "checked" status.
  #         (c) if tag is "select", get the subtree of that node.  They 
  #             should be "option" tags.  Scan through the "option" tags
  #             and compare either the "value" or the text of the node
  #             against each element of the array and set the "selected"
  #             status for those elements.
  #         (d) if tag is "textarea", set its text appropriately.
  #         (e) for everything else, set the "value" attribute appropriately.
  foreach my $name (sort keys (%$values))
    {
      my (@nodes) = $tree->find_by_attribute('name',$name);
      if ((scalar (@nodes)) > 0)
        {
          foreach my $node (@nodes)
            {
              my($tag) = $node->tag();
              my($type) = $node->attr('type');
              my($value) = $node->attr('value');

              if ((defined $type) && 
                  (($type eq 'checkbox') || ($type eq 'radio')))
                { # Steps (a) & (b)
                  $node->attr('checked',1) if ($value eq $values->{$name}[0]);
                }
              elsif ((defined $tag) && ($tag eq 'select'))
                { # Step (c)
                  my(@kids) = $node->content_list();
                  foreach my $kid (@kids)
                    { # Tricky! We want only the OPTION tag elements.
                      next if (!ref $kid);
                      if ($kid->tag() eq 'option')
                        { # Can have multiple selections!
                          foreach my $optval (@{ $values->{$name} })
                            {
                              $kid->attr('selected','1') if 
                                ((defined $kid->attr('value')) && 
                                 (($kid->attr('value') eq $optval) || 
                                  ($kid->as_text() =~  /^\s*$optval\s*$/)));
                            }
                        }
                    }
                }
              elsif ($tag eq 'textarea')
                { # Step (d)
                  $node->delete_content();
                  $node->push_content($values->{$name}[0]);
                }
              else
                { # Step (e)
                  $node->attr('value',$values->{$name}[0]);
                }
            }
        }
    }
}

#########################################################################
#  Subroutine: writeOutTempConfig                                       #
#  Parameter : An HTML::Tree tree to output to file                     #
#  Returns   : Nothing                                                  #
#  This subroutine takes in an HTML tree representing the combination   #
#  of the default HTML config file and the current config options       #
#  setttings.  It then writes out the tree to the file                  #
#  .configurator.temp.html, which is later read in and rendered.        #
#########################################################################
sub writeOutTempConfig # ($tree)
{
  my($tree) = @_;

  if (open(TREE,">$packagedir/.configurator.temp.html"))
    {
      print TREE $tree->as_HTML('<>&',"  ");
      close TREE;
    }
  else
    {
      carp("Couldn't write temporary HTML configuration file!");
      exitWithoutSaving();
    }
}

#########################################################################
#  Subroutine: writeOutConfigValues                                     #
#  Parameters: None                                                     #
#  Returns   : Nothing                                                  #
#  Call this subroutine when the user is finished entering values into  #
#  the form.  This subroutine takes those values and writes them out    #
#  to the .configurator.values file using XML::Simple.                  #
#########################################################################
sub writeOutConfigValues
{
  my $what;
  my %result;
  my $i = -1;
  my $foundit = 0;

  # Okay, I know this is a HUGE hack, but I couldn't really find an elegant
  # way to do what I needed to do.  Basically, I look through the horrible
  # "web" data structure (which is a Tk::Web object) for a bunch of 'Values'
  # (which are the values the user has set in the HTML Form).  I know that
  # this 'Values' array lives somewhere under the
  # {Configure}{-html}{_body}{_content} hash, but it changes depending on
  # the HTML file read in.  So, I increment through this array searching for
  # a defined hash named 'Values'. 
  do 
    {
      $i++;
      $foundit = ref $web->{'Configure'}{'-html'}{'_body'}{'_content'}[$i] &&
        defined ${$web->{'Configure'}{'-html'}{'_body'}{'_content'}[$i]}{'Values'};
    } until ($foundit) || ($i > 1000);

  return if ($i > 1000);  # Couldn't find it apparently. This shouldn't happen!

  # Okay, so now that I have found the array position, we treat this
  # horrible data structure as an array, loop through the values getting
  # name/value pairs which we can eventually write out to file.
  foreach $what 
    (@{${$web->{'Configure'}{'-html'}{'_body'}{'_content'}[$i]}{'Values'}})
    {
      my($name,$value) = @$what;
      my @val = (ref $value) ? $value->Call : $value;
      foreach $value (@val)
        {
          push(@{ $result{$name} },$value) if (defined $value);
        }
    }

  # We created the %result hash, now write it out to a Simple XML file.
  XMLout(\%result,
         outputfile => "$packagedir/.configurator.values",
         noescape => 1,
         rootname => 'config',
         noattr=> 1,
        ) if (scalar(keys %result) > 0);
}

#########################################################################
#  A convenience function called by loadHTMLFile to set the "Save"      #
#  button's state to 'active'.                                          #
#########################################################################
sub enableSaveButton
{
  $saveButton->configure(-state => 'active');
}

#########################################################################
#  Subroutine: loadHTMLFile                                             #
#  Parameter : The HTML file to display in the "web" window.            #
#  Returns   : Nothing                                                  #
#  Call this subroutine to read in an HTML file and render it in the    #
#  main "web" window.                                                   #
#########################################################################
sub loadHTMLFile # ($file)
{
  my ($file) = @_;

  if (($file) && (-s $file))
    {
      $web->url($file);   # Read in and render the file.
      # Set the title of the window
      if (ref $web->{Configure}{-html}{_head}{_content}[0])
        {
          $configLabel->configure(-text => 
            $web->{Configure}{-html}{_head}{_content}[0]{_content}[0]);
        }
      else
        {
          $configLabel->configure(-text => "Configuration");
        }
      $web->pack();

      # At program start, the 'Save' button is inactive.  When the
      # user clicks ANYTHING in the main "web" window, set it active.
      if (($web->configure(-state))[4] ne 'active')
        {
          # A click in the "web" window activates the button.
          $web->bind('<ButtonRelease-1>' => \&enableSaveButton);
          my (@kids) = $web->children;
          foreach my $kid (@kids)
            {
              # Argh! Every kid also needs to have an event tied to it!
              $kid->bind('<ButtonRelease-1>' => \&enableSaveButton);
            }
        }
    }
}

#########################################################################
#  Subroutine: displayWebPage                                           #
#  Parameters: 1. The parent widget which manages the config window.    #
#              2. The HTML file to display in the "web" window.         #
#  Returns   : Nothing                                                  #
#  Call this subroutine to display the "web" window when the program    #
#  first starts up.  This then calls loadHTMLFile to read in the        #
#  actual file and render it.                                           #
#########################################################################
sub displayWebPage # ($parent,$file)
{
  my ($parent,$file) = @_;

  # Check to see if our toplevel config window has been created yet.
  if (!$top)
    { # Create the toplevel window just once.
      if ($parent)
        {
          $top = $parent->Toplevel(-title => 'Configuration');
        }
      else
        { # If no parent, then create a MainWindow at the top.
          $top = MainWindow->new();
          $top->title("Configuration");
        }
      $top->withdraw;
      OSCAR::Configbox::Configbox_ui $top;  # Call the specPerl window creator
    }

  # The Save button should be disabled upon first display
  $saveButton->configure(-state => 'disabled');

  # Check to see if the "web" window frame has been created yet.
  if (!$web)
    { # Then create the web box
      $web = Tk::Web->new($configFrame);
      # What kind of files will this "web" window render?
      $web->{'-header'} = {'Accept' => join(',','text/html','text/plain',
                                                'image/gif','image/x-xbitmap',
                                                'image/x-pixmap','*/*'
                                           ),
                           };
      $web->pack(-expand => '1', -fill => 'both');
      $web->configure(-height => '15',
                      -width => '60',
                      -cursor => 'left_ptr',
                     );
      # Add optional scrollbars to the bottom and right sides.
      $root->AddScrollbars($web);
      $root->configure(-scrollbars => 'osoe');
    }

  # Load in and render the HTML file.
  loadHTMLFile($file);
  center_window( $top );  # Put the window on the screen.
}

#########################################################################
#  Subroutine: configurePackage                                         #
#  Parameters: 1. The parent of the Config Box (eg. $top or $root).     #
#              2. The full path for an OSCAR package's directory.       #
#  Returns   : Nothing                                                  #
#  This subroutine takes the full path name of a subdirectory under the #
#  OSCAR "packages" directory and attempts to render the configuration  #
#  HTML file to allow for package configuration.                        #
#########################################################################
sub configurePackage 
{
  my $parent = shift;
  $packagedir = shift;

  # Check for the configuration HTML file
  return if ((-s "$packagedir/.selection.ignore") ||
    (!(-s "$packagedir/configurator.html")));

  my($tree) = readInDefaultConfig("$packagedir/configurator.html");
  return if (!$tree);
  my($values) = readInConfigValues("$packagedir/.configurator.values");
  preprocessConfig($tree,$values) if $values;
  writeOutTempConfig($tree);
  $tree->delete;    # Always delete the tree when you are done with it.

  displayWebPage($parent,"$packagedir/.configurator.temp.html");
}


#configurePackage($top,'/home/tfleury/develop/oscar/packages/kernel_picker');


	# end additional interface code
}
#OSCAR::Configbox_ui $top;
#Tk::MainLoop;

1;
