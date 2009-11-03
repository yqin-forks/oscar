package OSCAR::ImageMgt;

#
# Copyright (c) 2007-2009 Geoffroy Vallee <valleegr@ornl.gov>
#                         Oak Ridge National Laboratory
#                         All rights reserved.
#
#   $Id$
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
# This package provides a set of function for OSCAR image management. This has
# initialy be done to avoid code duplication between the CLI and the GUI.
#

BEGIN {
    if (defined $ENV{OSCAR_HOME}) {
        unshift @INC, "$ENV{OSCAR_HOME}/lib";
    }
}

use strict;
use lib "/usr/lib/systeminstaller","/usr/lib/systemimager/perl";
use OSCAR::Logger;
use OSCAR::PackagePath;
use OSCAR::Database;
use OSCAR::Utils;
use OSCAR::ConfigManager;
# use SystemImager::Server;
use OSCAR::Opkg;
use SystemInstaller::Utils;
use OSCAR::PackMan;
use vars qw(@EXPORT);
use base qw(Exporter);
use Carp;
use warnings "all";

@EXPORT = qw(
            create_image
            delete_image
            do_setimage
            do_post_image_creation
            do_oda_post_install
            export_image
            get_image_default_settings
            get_list_corrupted_images
            get_list_images
            image_exists
            install_opkgs_into_image
            update_grub_config
            update_image_initrd
            update_kernel_append
            update_modprobe_config
            update_systemconfigurator_configfile
            );

our $images_path = "/var/lib/systemimager/images";
my $verbose = $ENV{OSCAR_VERBOSE};

################################################################################
# Set the image in the Database.                                               #
#                                                                              #
# Parameter: img, image name.                                                  #
#            options, hash with option values.                                 #
# Return   : 0 if sucess, -1 else.                                             #
################################################################################
sub do_setimage ($%) {
    my ($img, %options) = @_;
    my @errors = ();

    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        carp "ERROR: Impossible to get the OSCAR configuration\n";
        return -1;
    }
    my $config = $oscar_configurator->get_config();

    if ($config->{db_type} eq "db") {
        my $master_os = OSCAR::PackagePath::distro_detect_or_die("/");
        my $arch = $master_os->{arch};

        # Get the image path (typically
        # /var/lib/systemimager/images/<imagename>)
        my $config = SystemInstaller::Utils::init_si_config();
        my $imaged = $config->default_image_dir;
        croak "default_image_dir not defined\n" unless $imaged;
        croak "$imaged: not a directory\n" unless -d $imaged;
        croak "$imaged: not accessible\n" unless -x $imaged;
        my $imagepath = $imaged."/".$img;
        croak "$imagepath: not a directory\n" unless -d $imagepath;
        croak "$imagepath: not accessible\n" unless -x $imagepath;

        #
        # Image info lines should be deleted once systeminstaller
        # talks directly to ODA
        #
        my %image_info = ( "name"        => $img,
                #
                # EF: OS_Detect detects images now, use that!
                #
                # "distro"=>"$distroname-$distroversion",
                "architecture" => $arch,
                "path"         => $imagepath);

        OSCAR::Database::set_images(\%image_info, \%options, \@errors);
    } elsif ($config->{db_type} eq "file") {
        return 0;
    } else {
        carp "ERROR: Unknow ODA type ($config->{db_type})\n";
        return -1;
    }
    return 0;
}

################################################################################
# Simple wrapper around post_install; make sure we call correctly the script.  #
#                                                                              #
# Input: img, image name.                                                      #
#        interface, network interface id used by OSCAR.                        #
# Return: 1 if success, 0 else.                                                #
################################################################################
sub do_post_image_creation ($$) {
    my $img = shift;
    my $interface = shift;
    my $cwd = `/bin/pwd`;

    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        carp "ERROR: Impossible to get the OSCAR configuration\n";
        return 0;
    }
    my $config = $oscar_configurator->get_config();

    chdir "$config->{binaries_path}";
    my $cmd = "$config->{binaries_path}/post_rpm_install $img $interface --verbose";

    if (system($cmd)) {
        carp "ERROR: Impossible to execute $cmd";
        delete_image($img);
        return 0;
    }
    OSCAR::Logger::oscar_log_subsection("Successfully ran: $cmd");

    chdir "$cwd";
    return 1;
}

################################################################################
# Input: vars, hash with variable values.                                      #
#        options, hash with option values.                                     #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub do_oda_post_install ($$) {
    my ($vars, $options) = @_;
    my @errors = ();
    my $img = $$vars{imgname};

    # Have installed Client binary packages and did not croak, so mark
    # packages. <pkg>installed # true. (best effort for now)

    oscar_log_subsection("Marking installed bit in ODA for client binary ".
                         "packages");

    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        carp "ERROR: Impossible to get the OSCAR configuration\n";
        return -1;
    }
    my $config = $oscar_configurator->get_config();

    if ($config->{db_type} eq "db") {
        my @opkgs = list_selected_packages();
        foreach my $opkg (@opkgs)
        {
            oscar_log_subsection("Set package: $opkg");
            OSCAR::Database::set_image_packages($img,
                                                $opkg,
                                                $options,
                                                \@errors);
        }
    } elsif ($config->{db_type} eq "db") {
        # Get the list of opkgs for the specific image.
    } else {
        carp "ERROR: Unknow ODA type ($config->{db_type})\n";
        return -1
    }
    oscar_log_subsection("Done marking installed bits in ODA");

    #/var/log/lastlog could be huge in some horked setup packages...
    croak "Image name not defined\n" unless $img;
    my $lastlog = "/var/log/lastlog";
    oscar_log_subsection("Truncating ".$img.":".$lastlog);

    my $sis_config = SystemInstaller::Utils::init_si_config();
    my $imaged = $sis_config->default_image_dir;
    my $imagepath = $imaged."/".$img;
    my $imagelog = $imagepath.$lastlog;
    truncate $imagelog, 0 if -s $imagelog;
    oscar_log_subsection("Truncated ".$img.":".$lastlog);

    return 0;
}

###############################################################################
# Get the fstab stuff based on the architecture and the type of disk          #
# Input: arch, target architecture.                                           #
#        disk_type, target disk type (e.g. IDE, SCSI).                        #
# Return: file path the fstab stuff.                                          #
###############################################################################
sub get_disk_file {
    my ($arch, $disk_type) = @_;

    my $diskfile;
    if ($ENV{OSCAR_HOME}) {
        $diskfile = "$ENV{OSCAR_HOME}/oscarsamples/$disk_type";
    } else {
        $diskfile = "/usr/share/oscar/oscarsamples/$disk_type";
    }
    #ia64 needs special disk file because of /boot/efi
    $diskfile .= ".$arch" if $arch eq "ia64";
    $diskfile .= ".disk";

    return $diskfile;
}

sub get_binary_list_file ($) {
    my $os = shift;

    if (!defined $os) {
        carp "ERROR: Undefined os variable";
        return undef;
    }

    my $oscarsamples_dir;
    if (defined $ENV{OSCAR_HOME}) {
        $oscarsamples_dir = "$ENV{OSCAR_HOME}/oscarsamples";
    } else {
        $oscarsamples_dir = "/usr/share/oscar/oscarsamples";
    }

    # We look if a package file exists for the exact distro we use. If not, we
    # use the package file for the compat distro.
    my $distro = $os->{distro};
    my $distro_ver = $os->{distro_version};
    my $distro_update = $os->{distro_update}; #this is optinal
    my $compat_distro = $os->{compat_distro};
    my $compat_distro_ver = $os->{compat_distrover};
    my $arch = $os->{arch};
    if (!OSCAR::Utils::is_a_valid_string ($distro) ||
        !OSCAR::Utils::is_a_valid_string ($distro_ver) ||
        !OSCAR::Utils::is_a_valid_string ($compat_distro) ||
        !OSCAR::Utils::is_a_valid_string ($compat_distro_ver) ||
        !OSCAR::Utils::is_a_valid_string ($arch)) {
        carp "ERROR: Impossible to extract distro information";
        return undef;
    }
    my $version = $distro_ver;
    $version = "$version.$distro_update" if (defined ($distro_update));
    my $pkglist = "$oscarsamples_dir/".
                  "$distro-$version-$arch.rpmlist";
    if (! -f $pkglist) {
        $pkglist = "$oscarsamples_dir/".
                   "$compat_distro-$compat_distro_ver-$arch.rpmlist";
    }

    oscar_log_subsection("Identified distro of clients: $distro $distro_ver");

    return $pkglist;
}

################################################################################
# Get the default settings for the creation of new images.                     #
# !!WARNNING!! We do not set postinstall and title. The distro is also by      #
# default the local distro.                                                    #
# Input: none.                                                                 #
# Output: default settings (via a hash).                                       #
#         The format of the hash is the following is available within the code.#
################################################################################
sub get_image_default_settings () {
    # /tmp/error is provided if any error; further fdisk may produce
    # certain output such as raid partitions, but the following check should
    # work for grepping /dev/sd, further the check should also work when LVM
    # partitions. Replacing the previous "df" check.
    
    my @df_lines = `fdisk -l 2> /tmp/error |grep Disk`;
    my $disk_type = "ide";
    $disk_type = "scsi" if (grep(/\/dev\/sd/,(@df_lines)));

    #Get the distro list
    my $master_os = OSCAR::OCA::OS_Detect::open ("/");
    if (!defined $master_os) {
        carp "ERROR: Impossible to detect the distro on the headnode";
        return undef;
    }

    OSCAR::Utils::print_hash ("", "", $master_os) if ($verbose);

    my $arch = $master_os->{arch};
    my $pkglist = get_binary_list_file($master_os);

    my $distro_pool = OSCAR::PackagePath::distro_repo_url();
    $distro_pool =~ s/\ /,/g;
    my $oscar_pool = OSCAR::PackagePath::oscar_repo_url();

    oscar_log_subsection("Distro repo: $distro_pool");
    oscar_log_subsection("OSCAR repo: $oscar_pool");
    oscar_log_subsection("Using binary list: $pkglist");

    # Get a list of client RPMs that we want to install.
    # Make a new file containing the names of all the RPMs to install

#     my $outfile = "/tmp/oscar-install-rpmlist.$$";
#     create_list_selected_opkgs ($outfile);
#     my @errors;
#     my $save_text = $outfile;
#     my $extraflags = "--filename=$outfile";
    # WARNING!! We deactivate the OPKG management via SystemInstaller
    my $extraflags = "";
    if (exists $ENV{OSCAR_VERBOSE}) {$extraflags .= " --verbose ";}

    my $diskfile = get_disk_file($arch, $disk_type);

    my $config = SystemInstaller::Utils::init_si_config();

    # Default settings
    my %vars = (
           # imgpath: location where the image is created
           imgpath => $config->default_image_dir,
           # imgname: image name
           imgname => "oscarimage",
           # arch: target hardware architecture
           arch => $arch,
           # pkgfile: location of the file giving the list of binary package
           # for the creation of the image
           pkgfile => $pkglist,
           # pkgpath: path of the different binary packages pools used for the
           # creation of the image.
           pkgpath => "$oscar_pool,$distro_pool",
           # diskfile: path to the file that gives the disk partition layout.
           diskfile => $diskfile,
           # ipmeth: method to assign the IP (possible options are: "static")
           # TODO: check what are the other possible options
           ipmeth => "static",
           # piaction: action to perform when the image is deployed (possible
           # options are: "reboot").
           # TODO: check what are the other possible options
           piaction => "reboot",
           # extraflags: string for extra SIS flags. Should be used only for the
           # tricky stuff.
           extraflags => $extraflags
           );

    return %vars;
}

###############################################################################
# Get the list of images from the SIS database (which is used to drive and    #
# settup SystemImager.                                                        #
#                                                                             #
# Input: None.                                                                #
# Return: List of images in the SIS database (via an array of image names),   #
#         undef if error.                                                     #
###############################################################################
sub get_systemimager_images () {
    my $sis_cmd = "/usr/bin/si_lsimage";
    my @sis_images = `$sis_cmd`;
    my $i;

    #We do some cleaning...
    # We remove the three useless lines of the result
    for ($i=0; $i<3; $i++) {
        shift (@sis_images);
    }
    # We also remove the last line which is an empty line
    pop (@sis_images);
    # Then we remove the return code at the end of each array element
    # We also remove the 2 spaces before each element
    foreach $i (@sis_images) {
        chomp $i;
        $i = substr ($i, 2, length ($i));
    }

    return @sis_images;
}

################################################################################
# Delete an existing image.                                                    #
# Input: imgname, image name.                                                  #
# Output: 0 if success, -1 else.                                               #
# TODO: We need to update the OSCAR database when deleting an image.           #
################################################################################
sub delete_image ($) {
    my $imgname = shift;

    # If the image exists at the SystemImager level, we delete it
    my @si_images = get_systemimager_images ();
    if (OSCAR::Utils::is_element_in_array ($imgname, @si_images) == 1) {
        my $config = SystemInstaller::Utils::init_si_config();
        my $rsyncd_conf = $config->rsyncd_conf();
        my $rsync_stub_dir = $config->rsync_stub_dir();

        my $cmd = "/usr/bin/mksiimage -D --name $imgname --force";
        if (system($cmd)) {
            carp "ERROR: Impossible to execute $cmd";
            return -1;
        }
        require SystemImager::Server;
        SystemImager::Server::remove_image_stub($rsync_stub_dir, $imgname);
        SystemImager::Server::gen_rsyncd_conf($rsync_stub_dir, $rsyncd_conf);
    }

    # We remove the image from ODA.
    my $sql = "DELETE FROM Images WHERE Images.name='$imgname'";
    if (OSCAR::Database::do_update($sql,"Images", undef, undef) == 0) {
        carp "ERROR: Impossible to execute the SQL command $sql";
        return -1;
    }

    return 0;
}

################################################################################
# Get the list of corrupted images. An image is concidered corrupted when info #
# from the OSCAR database, the SIS database and the file system are not        #
# synchronized.                                                                #
#                                                                              #
# Input: None.                                                                 #
# Output: an array of hash; each element of the array (hash) has the following #
#         format ( 'name' => <image_name>,                                     #
#                  'oda' => "ok"|"missing",                                    #
#                  'sis' => "ok"|"missing",                                    #
#                  'fs' => "ok"|"missing" ).                                   #
#         undef if error.                                                      #
################################################################################
sub get_list_corrupted_images {
    my @result;
    my @sis_images = get_systemimager_images ();
    my $image_name;
    my %entry;

    # The array is now clean, we can print it
    print "List of images in the SIS database: ";
    print_array (@sis_images);

    my @tables = ("Images");
    my @oda_images = ();
    my @res = ();
    my $cmd = "SELECT Images.name FROM Images";
    if ( OSCAR::Database::single_dec_locked( $cmd,
                                             "READ",
                                             \@tables,
                                             \@res,
                                             undef) ) {
    # The ODA query returns a hash which is very unconvenient
    # We transform the hash into a simple array
    foreach my $elt (@res) {
        # It seems that we always have an empty entry, is it normal?
        if ($elt->{name} ne "") {
            push (@oda_images, $elt->{name});
        }
    }
    print "List of images in ODA: ";
    print_array (@oda_images);
    } else {
        carp ("ERROR: Cannot query ODA\n");
        return undef;
    }

    # We get the list of images from the file system
    my $sis_image_dir = "/var/lib/systemimager/images";
    my @fs_images = ();
    if ( ! -d $sis_image_dir ) {
        carp ("ERROR: The image directory does not exist ".
              "($sis_image_dir)");
        return undef;
    }
    opendir (DIRHANDLER, "$sis_image_dir")
        or (carp ("ERROR: Impossible to open $sis_image_dir"), return undef);
    foreach my $dir (sort readdir(DIRHANDLER)) {
        if ($dir ne "."
            && $dir ne ".."
            && $dir ne "ACHTUNG"
            && $dir ne "DO_NOT_TOUCH_THESE_DIRECTORIES"
            && $dir ne "CUIDADO"
            && $dir ne "README") {
            push (@fs_images, $dir);
        }
    }
    print "List of images in file system: ";
    print_array (@fs_images);

    # We now compare the lists of images
    foreach $image_name (@sis_images) {
        %entry = ('name' => $image_name,
                     'sis' => "ok",
                     'oda' => "ok",
                     'fs' => "ok");
        if (!is_element_in_array($image_name, @oda_images)) {
            $entry{'oda'} = "missing";
        }
        if (!is_element_in_array($image_name, @fs_images)) {
            $entry{'fs'} = "missing";
        }
        push (@result, \%entry);
    }

    foreach $image_name (@oda_images) {
        %entry = ('name' => $image_name,
                     'sis' => "ok",
                     'oda' => "ok",
                     'fs' => "ok");
        if (!is_element_in_array($image_name, @sis_images)) {
            $entry{'sis'} = "missing";
        }
        if (!is_element_in_array($image_name, @fs_images)) {
            $entry{'fs'} = "missing";
        }
        push (@result, \%entry);
    }

    foreach $image_name (@fs_images) {
        %entry = ('name' => $image_name,
                     'sis' => "ok",
                     'oda' => "ok",
                     'fs' => "ok");
        if (!is_element_in_array($image_name, @sis_images)) {
            $entry{'sis'} = "missing";
        }
        if (!is_element_in_array($image_name, @oda_images)) {
            $entry{'oda'} = "missing";
        }
        push (@result, \%entry);
    }

    return (@result);
}

sub get_list_images () {
    my @tables = ("Images");
    my @res = ();
    my $sql = "SELECT * FROM Images";
    if (!OSCAR::Database::single_dec_locked( $sql,
                                             "READ",
                                             \@tables,
                                             \@res,
                                             undef) ) {
        carp "ERROR: Impossible to execute the SQL command $sql";
        return undef;
    }

    # We reformat the result just to get the list of image names.
    my @images;
    foreach my $i (@res) {
        push (@images, $i->{'name'});
    }

    return @images;
}

################################################################################
# Check if a given image exists.                                               #
#                                                                              #
# Input: image_name, name of the image to check.                               #
# Return: 1 if the image already exists (true), 0 else (false), -1 if error.   #
# TODO: We should check in ODA and not the filesystem.                         #
################################################################################
sub image_exists ($) {
    my $image_name = shift;

    if (!OSCAR::Utils::is_a_valid_string ($image_name)) {
        carp "ERROR: Invalid image name";
        return -1;
    }

    my @tables = ("Images");
    my @res = ();
    my $sql = "SELECT Images.name FROM Images WHERE Images.name='$image_name'";
    if ( OSCAR::Database::single_dec_locked( $sql,
                                             "READ",
                                             \@tables,
                                             \@res,
                                             undef) ) {
        if (scalar (@res) == 1) {
            return 1;
        } elsif (scalar (@res) == 0) {
            return 0;
        } else {
            carp "ERROR: found ".scalar(@res)." images named $image_name";
            return -1;
        }
    }
    carp "ERROR: Impossible to query ODA";
    return -1;
}

################################################################################
# Function that makes sure /proc is not mounted within an image.               #
#                                                                              #
# Input: image_path, path to the image.                                        #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub umount_image_proc ($) {
    my $image_path = shift;
    my $proc_status = 0; # tells if /proc is mounted or not (0 = not mounted,
                         # 1 = mounted)
    my $cmd = "/usr/sbin/chroot $image_path mount";
    my @lines = split ('\n', `$cmd`);

    foreach my $line (@lines) {
        if ($line =~ /^proc/) {
            $proc_status = 1;
            last;
        }
    }

    if ($proc_status == 1) {
        $cmd = "/usr/sbin/chroot $image_path umount /proc";
        system ($cmd); # we do not check the return code because when creating
                       # the image, the status of /proc may not be coherent, so
                       # the command returns an error but this is just fine.
    }

    return 0;
}

################################################################################
# This function aims to clean up the image after creation. For instance, it    #
# will ensure that /proc is not mounted anymore.                               #
#                                                                              #
# Input: vars, image configuration hash.                                       #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub image_cleanup ($) {
    my $vars = shift;

    my $image_path = "$$vars{imgpath}/$$vars{imgname}";

    # Step 1: we make sure /proc is not mounted in the image
    if (umount_image_proc ($image_path)) {
        carp "ERROR: Impossible to umount /proc ($image_path)";
        return -1;
    }

    return 0;
}

################################################################################
# Create a basic image.                                                        #
#                                                                              #
# Input: image. image name to create.                                          #
#        vars, image configuration hash.                                       #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub create_image ($%) {
    my ($image, %vars) = @_;

    # We create a basic image for clients. Note that by default we do not
    # create a basic image for servers since the server may already be deployed.
    # We currently use the script 'build_oscar_image_cli'. This is a limitation
    # because it only creates an image based on the local Linux distribution.
    oscar_log_section "Creating the basic golden image..." if $verbose;

    $vars{imgname} = "$image";
    $verbose = 1;

    my $image_path = "$vars{imgpath}/$vars{imgname}";
    my $cmd = "mksiimage -A --name $vars{imgname} " .
            "--filename $vars{pkgfile} " .
            "--arch $vars{arch} " .
            "--path $image_path ";
    $cmd .= "--distro $vars{distro} " if defined $vars{distro};
    if (!defined $vars{distro} && defined $vars{pkgpath}) {
        $cmd .= "--location $vars{pkgpath} ";
    }
    $cmd .= " $vars{extraflags} --verbose";

    oscar_log_subsection "Executing command: $cmd" if $verbose;
    if (system ($cmd)) {
        carp "ERROR: Impossible to create the image ($cmd)\n";
        return -1;
    }

    # Add image data into ODA
    my %image_data = ("name" => $image,
                      "path" => "$vars{imgpath}/$vars{imgname}",
                      "architecture" => "$vars{arch}");
    if (OSCAR::Database::set_images (\%image_data, undef, undef) != 1) {
        carp "ERROR: Impossible to store image data into ODA";
        return -1;
    }

    # We now install selected non-core OPKGs
    my @core_opkgs = OSCAR::Opkg::get_list_core_opkgs();
    my %selection_data
        = OSCAR::Database::get_opkgs_selection_data (undef);
    print "[INFO] no selected OPKGs\n" if (keys %selection_data == 0);
    my $os = OSCAR::OCA::OS_Detect::open(chroot=>"$image_path");
    if (!defined $os) {
        carp "ERROR: Impossible to detect the distro id for $image_path";
        return -1;
    }
    my $distro_id = OSCAR::PackagePath::os_distro_string ($os);
    if (!OSCAR::Utils::is_a_valid_string ($distro_id)) {
        carp "ERROR: Impossible to get the distro ID based on the detected os";
        return -1;
    }
    # If we do not have yet selection data for some OPKGs, we assign the default
    # selection (selected for core OPKGs, unselected for others).
    require OSCAR::RepositoryManager;
    my $rm = OSCAR::RepositoryManager->new (distro=>$distro_id);
    my ($rc, @output);
    require OSCAR::ODA_Defs;
    foreach my $opkg (keys %selection_data) {
        if (!OSCAR::Utils::is_element_in_array ($opkg, @core_opkgs)) {
            if ($selection_data{$opkg} eq OSCAR::ODA_Defs::SELECTED()) {
                print "Installing opkg-$opkg-client into the image...\n";
                ($rc, @output) = $rm->install_pkg ($image_path,
                                                   "opkg-$opkg-client");
                if ($rc) {
                    carp "ERROR: Impossible to install opkg-$opkg-client in ".
                         "$image_path (rc: $rc)";
                    return -1;
                }
            }
        }
    }

    # Deal with the harddrive configuration of the image
    $cmd = "mksidisk -A --name $vars{imgname} --file $vars{diskfile}";
    if( system($cmd) ) {
        carp("ERROR: Couldn't run command $cmd");
        return -1;
    }

    # Now we execute the post image creation actions.
    if (postimagebuild (\%vars)) {
        carp "ERROR: Impossible to run postimagebuild";
        return -1;
    }

    # We make sure everything is fine with the image
    if (image_cleanup (\%vars)) {
        carp "ERROR: Impossible to cleanup the image after creation";
        return -1;
    }

    oscar_log_subsection "OSCAR image successfully created";

    return 0;
}

################################################################################
# SystemConfigurator has a bad limitation: the label for the default kernel    #
# has a limitation on its length. So we check this length and we update it if  #
# needed.                                                                      #
#                                                                              #
# Input: full path of the SystemConfigurator config file to analyze.           #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub update_systemconfigurator_configfile ($) {
    my $file = shift;
    use constant MAX_LABEL_LENGTH  =>  12;

    if (! -f $file) {
        return 1;
    }

    require OSCAR::ConfigFile;
    my $default_boot = OSCAR::ConfigFile::get_value ($file,
                                                     "BOOT",
                                                     "DEFAULTBOOT");
    my $default_label = OSCAR::ConfigFile::get_value ($file,
                                                     "KERNEL0",
                                                     "LABEL");

    if (!defined ($default_boot) || !defined ($default_label)) {
        carp "ERROR: The file $file exists but does not have a default boot ".
             "or a default label";
        return -1;
    }

    if ($default_boot ne $default_label) {
        print STDERR "WARNING: the default boot kernel is not the kernel0 we ".
                     "do not know how to deal with that situation";
        return 1;
    }

    if (length ($default_boot) > MAX_LABEL_LENGTH) {
        if (OSCAR::ConfigFile::set_value($file,
                                         "BOOT",
                                         "DEFAULTBOOT",
                                         "default_kernel")) {
            carp "ERROR: Impossible to update the default boot kernel";
            return -1;
        }
        if (OSCAR::ConfigFile::set_value($file,
                                         "KERNEL0",
                                         "LABEL",
                                         "default_kernel")) {
            carp "ERROR: Impossible to update the label of the default kernel";
            return -1;
        }
    }

    return 0;
}

################################################################################
# Update the etc/systemconfig/systemconfig.conf file of a given image to       #
# include some kernel parameters (the APPEND option).                          #
#                                                                              #
# Return: 0 if success, -1 else.                                               #
# TODO: we currently assume only one kernel is setup. Yes this is lazy and     #
# this needs to be updated                                                     #
################################################################################
sub update_kernel_append ($$) {
    my ($imgdir, $append_str) = @_;

    oscar_log_subsection ("Adding boot parameter ($append_str) for image ".
                          "$imgdir");
    my $file = "$imgdir/etc/systemconfig/systemconfig.conf";
    require OSCAR::ConfigFile;
    if (OSCAR::ConfigFile::set_value ($file, "KERNEL0", "\tAPPEND",
                                      "\"$append_str\"")) {
        carp "ERROR: Impossible to add $append_str as boot parameter in $file";
        return -1;
    }

    return 0;
}

################################################################################
# Make sure the basic GRUB files exists into a given image (some distro are    #
# more picky than others.                                                      #
#                                                                              #
# Input: Path, path to the image.                                              #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub update_grub_config ($) {
    my $path = shift;

    $path .= "/boot";
    if (!-d $path) {
        carp "ERROR: $path does not exist";
        return -1;
    }

    $path .= "/grub";
    if (!-d $path) {
        mkdir $path;
    }

    $path .= "/menu.lst";
    if (!-f $path) {
        my $cmd = "touch $path";
        if (system $cmd) {
            carp "ERROR: Impossible to execute $cmd";
            return -1;
        }
    }

    return 0;
}

# This update the modprobe.conf file for a given image. The content that needs
# to be added is static since it currently only aims to enable the creation of
# a valid initrd for RHEL-5 based systems.
#
# Input: image_path, path of the image for which the update has to be done.
# Return: 0 if success, -1 else.
sub update_modprobe_config ($) {
    my $image_path = shift;
    my $cmd;

    if (! -d $image_path) {
        carp "ERROR: $image_path does not exist";
        return -1;
    }

    my $modprobe_conf = "$image_path/etc/modprobe.conf";
    my $content = "alias scsi_hostadapter1 amd74xx ata_piix";
    if (OSCAR::FileUtils::add_line_to_file_without_duplication (
            $content,
            $modprobe_conf)) {
        carp "ERROR: Impossible to add $content into $modprobe_conf";
        return -1;
    }

    return 0;
}

# Return: 0 if success, -1 else.
sub update_image_initrd ($) {
    my $imgpath = shift;
    my $cmd;

    # First we create a "fake" fstab. The problem is the following: nowadays,
    # binary packages for kernels try to create the initrd on the fly, based
    # on configuration data. This is not compliant with the old systemimager
    # idea where the initrd is created at the end of the image deployment. So
    # we trick the configuration to allow the kernel package to generate the
    # initrd.

    # Currently the problem has been reported only for RPM based distros
    my $os = OSCAR::OCA::OS_Detect::open ($imgpath);
    if (!defined $os) {
        carp "ERROR: Impossible to detect image distro ($imgpath)";
        return -1;
    }
    return 0 if ($os->{pkg} ne "rpm");

    if (! -d $imgpath) {
        carp "ERROR: Impossible to find the image ($imgpath)";
        return -1;
    }

    # The /etc/systemconfig/systemconfig.conf should exist in the image.    
    my $systemconfig_file = "$imgpath/etc/systemconfig/systemconfig.conf";
    if (! -f $systemconfig_file) {
        carp "ERROR: $systemconfig_file does not exist";
        return -1;
    }
    use OSCAR::ConfigFile;
    my $root_device = OSCAR::ConfigFile::get_value ($systemconfig_file,
        "BOOT", "ROOTDEV");
    if (!OSCAR::Utils::is_a_valid_string ($root_device)) {
        carp "ERROR: Impossible to get the default root device";
        return -1;
    }
    my $fake_fstab = "$imgpath/etc/fstab.fake";
    $cmd = "echo \"$root_device  /  ext3  defaults  1 1\" >> $fake_fstab";
    print "[INFO] Running $cmd...\n";
    if (system ($cmd)) {
        carp "ERROR: Impossible to execute $cmd";
        return -1;
    }
    if (! -f $fake_fstab) {
        carp "ERROR: $fake_fstab does not exist";
        return -1;
    }

    # TODO: We currently assume the kernel0 is the one we boot up, this is
    # not necessarily the case right now.
    my $initrd = OSCAR::ConfigFile::get_value ($systemconfig_file,
        "KERNEL0", "INITRD");
    my $version = OSCAR::ConfigFile::get_value ($systemconfig_file,
        "KERNEL0", "PATH");
    if (!OSCAR::Utils::is_a_valid_string ($version)) {
        carp "ERROR: Impossible to detect the image kernel version ($imgpath)";
        return -1;
    }
    if ($version =~ /\/boot\/vmlinuz-(.*)/) {
        $version = $1;
    } else {
        carp "ERROR: Impossible to get the version ($version)";
        return -1;
    }
    my $chroot_bin = "/usr/sbin/chroot";
    if (! -f $chroot_bin) {
        carp "ERROR: the chroot binary ($chroot_bin) is not available";
        return -1;
    }
    $cmd = "$chroot_bin $imgpath /sbin/mkinitrd -v -f --fstab=/etc/fstab.fake ".
           "--allow-missing $initrd $version";
    print "[INFO] Running $cmd...\n";
    if (system ($cmd)) {
        carp "ERROR: Impossible to execute $cmd";
        return -1;
    }

    return 0;
}

# Return: 0 if success, -1 else.
sub postimagebuild {
    my ($vars) = @_;
    my $img = $$vars{imgname};
    my $interface;
    my %options;

    require OSCAR::ConfigFile;
    $interface = OSCAR::ConfigFile::get_value ("/etc/oscar/oscar.conf",
                                               undef,
                                               "OSCAR_NETWORK_INTERFACE");

    OSCAR::Logger::oscar_log_subsection ("Setting up image in the database");
    if (do_setimage ($img, %options)) {
        carp "ERROR: Impossible to set image";
        return -1;
    }

    if (do_post_image_creation ($img, $interface) == 0) {
        carp "ERROR: Impossible to do post binary package install, ".
             "deleting the image...";
        if (delete_image ($img)) {
            carp "ERROR: Impossible to delete image $img";
        }
        return -1;
    }

    if (do_oda_post_install ($vars, \%options)) {
        carp "ERROR: Impossible to update data in ODA, deleting image...";
        if (delete_image ($img)) {
            carp "ERROR: Impossible to delete image $img";
        }
        return -1;
    }

    return 0;
}

################################################################################
# Install a given list of OPKGs into a golden image. We assume for now that we #
# have to install the client side of those OPKGs.                              #
#                                                                              #
# Input: partition, the image name in which we need to install OPKGs.          #
# Return: 0 if success, -1 else.                                               #
#                                                                              #
# TODO: remove the hardcoded image path. SIS provides a tool for that.         #
################################################################################
sub install_opkgs_into_image ($@) {
    my ($image, @opkgs) = @_;

    # We check first if parameters are valid.
    if (!defined($image) || $image eq "" ||
        !@opkgs) {
        carp "ERROR: Invalid parameters\n";
        return -1;
    }

    my $image_path = "$images_path/$image";
    oscar_log_section "Installing OPKGs into image $image ($image_path)";
    oscar_log_subsection "List of OPKGs to install: ". join(" ", @opkgs);

    # To install OPKGs, we use Packman, creating a specific packman object for
    # the image.
    my $pm = PackMan->new->chroot ($image_path);
    if (!defined ($pm)) {
        carp "ERROR: Impossible to create a Packman object for the ".
             "installation of OPKGs into the golden image\n";
        return -1;
    }

    # We assign the correct repos to the PacjMan object.
    my $os = OSCAR::OCA::OS_Detect::open(chroot=>$image_path);
    if (!defined ($os)) {
        carp "ERROR: Impossible to detect the OS of the image ($image_path)\n";
        return -1;
    }
    my $image_distro = "$os->{distro}-$os->{distro_version}-$os->{arch}";
    oscar_log_subsection "Image distro: $image_distro";
    require OSCAR::RepositoryManager;
    my $rm = OSCAR::RepositoryManager->new (distro=>$image_distro);

    # GV: do we need to install only the client side of the OPKG? or do we also
    # need to install the api part.
    foreach my $opkg (@opkgs) {
        oscar_log_subsection "\tInstalling $opkg using opkg-$opkg-client"
            if $verbose;
        # Once we have the packman object, it is fairly simple to install opkgs.
        my ($ret, @out) = $rm->install_pkg($image_path, "opkg-$opkg-client");
        if ($ret) {
            carp "ERROR: Impossible to install OPKG $opkg:\n".join("\n", @out);
            return -1;
        }
    }

    return 0;
}

################################################################################
# Export the image for a given partition. This image can then be used outside  #
# of OSCAR. The export typically creates a tarball having the file system of   #
# partition. The name of the partition is image-<partition_id>.tar.gz.         #
#                                                                              #
# Input: partition, partition identifier (typically its name).                 #
#        dest, directory where the tarball will be created. Note that the      #
#        directory is also used as temporary directory while creating the      #
#        image, that can require a lot of disk space.                          #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub export_image ($$) {
    my ($partition, $dest) = @_;

    if (!defined ($partition) || !defined ($dest)) {
        carp "ERROR: Invalid arguments";
        return -1;
    }

    my $tarball = "$dest/image-$partition.tar.gz";
    my $temp_dir = "$dest/temp-$partition";

    require File::Path;

    if (! -d $dest) {
        carp "ERROR: the destination directory does not exist";
        return -1;
    }
    if (-f $tarball) {
        carp "ERROR: the tarball already exists ($tarball)";
        return -1;
    }

    if (image_exists ($partition) == 1) {
        oscar_log_subsection "INFO: The image already exists" if $verbose;

        # the image already exists we just need to create the tarball
        my $cmd = "cd $images_path/$partition; tar czf $tarball *";
        oscar_log_subsection "Executing: $cmd" if $verbose;
        if (system ($cmd)) {
            carp "ERROR: impossible to create the tarball";
            return -1;
        }
    } else {
        oscar_log_subsection "INFO: the image does not exist" if $verbose;
        if (-d $temp_dir) {
            rmtree ($temp_dir);
        }

        # We get the default settings for images.
        my %image_config = OSCAR::ImageMgt::get_image_default_settings ();
        if (!%image_config) {
            carp "ERROR: Impossible to get default image settings\n";
            return -1;
        }
        $image_config{imgpath} = $temp_dir;
        # If the image does not already exists, we create it.
        if (OSCAR::ImageMgt::create_image ($partition, %image_config)) {
            carp "ERROR: Impossible to create the basic image\n";
            rmtree ($temp_dir);
            return -1;
        }

        # the image is ready to be tared!
        my $cmd = "cd $temp_dir; tar czf $tarball *";
        oscar_log_subsection "Executing: $cmd" if $verbose;
        if (system ($cmd)) {
            carp "ERROR: impossible to create the tarball";
            rmtree ($temp_dir);
            return -1;
        }

        rmtree ($temp_dir);
    }
    return 0;
}

1;

__END__

=head1 NAME

ImageMgt - a set of functions for the management of images in OSCAR.

=head1 SYNOPSIS

The available functions are:

    create_image
    delete_image
    do_setimage
    do_post_image_creation
    do_oda_post_install
    export_image
    get_image_default_settings
    get_list_corrupted_images
    image_exists
    install_opkgs_into_image
    upgrade_grub_config
    update_systemconfigurator_configfile

